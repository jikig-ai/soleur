---
title: "ci: take the AC6 drift guard and the ADR-232 bump target from the semver-max vinngest-v* tag merged into main"
date: 2026-09-27
slug: ci-vinngest-semver-max-merged-into-main
branch: feat-one-shot-8782-vinngest-semver-max-merged
issue: 8782
closes: 8782
type: ci
priority: P2
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

# ci: take the AC6 drift guard and the ADR-232 bump target from the semver-max `vinngest-v*` tag merged into main

## Enhancement Summary

**Deepened on:** 2026-09-27.
**Inputs:**
- plan-review panel: DHH, Kieran, code-simplicity, CTO devex;
- scoped advisor consult;
- deepen agents: scratch-clone prototype, `soleur:engineering:review:test-design-reviewer`, cheap-tier claims sweep.

### Key improvements

1. **The rewrite list is now measured, not predicted.** The scratch-clone prototype applied Phases 2 and 3.1 and ran the unmodified suite: 377 pass, 40 fail, across exactly B1, B2, B3, B7, B7a, B8, B12 and the `g2.parity` literal row. No row outside the plan's list fails. B13 already passes (its needles survive), so it leaves the Expected-RED list. B7's new outcome is confirmed: `resolve`, both needles, crane and gh never called. The live AC6 with `--merged HEAD` passes in the clone (pin = merged-max = `v1.1.40`).
2. **Mechanisms cut at plan-review.** The decidability probe, the signed-tag notice, the deferral narrowing (B22/B23), the AC6 shallow arm, the census row, the old-literal row, the 11-row selector fixture matrix and the `merge-base` call were all removed. The literal parity loop becomes directional byte-equality of the shipped selector blocks.
3. **Test-design hardening:**
   - B8 now shadows the **target** tag, so it still tests the bare-name peel.
   - B9b's needle is unique to the moved shallow check.
   - B7 and B7a carry git-output preconditions.
   - `assert_refused` takes a stage argument.
   - Guard 1 closes its former M7 residual.

### New considerations discovered

- Under `set -u`, the shallow-check message must not reference `TARGET` or `${tag}`: it now runs before either is set.
- `awk -v` mangles the slicer regex, so the pattern goes through `ENVIRON`.
- A missing mid-history object makes `git tag --merged` fail **entirely** (empty output, rc 0), even for tags below the hole. A missing tag commit drops only that tag.
- Every claim swept checks out: the rule IDs, the cited paths, the PR and issue states, the ADR-232 AC7 regex (matches exactly lines 34 and 201, not the 2026-09-24 amendment), the runbook and C4 needle counts (1 each), `deploy-script-tests` absent from any ruleset, the `g1.defer` needles, and the operand-census count staying at 1.

The spec had no valid `lane:`, so this plan defaults to `cross-domain` (TR2 fail-closed). No `spec.md` exists for this one-shot branch.

## Overview

Two places pick the "latest" `vinngest-v*` tag:

- the **AC6 drift guard** in `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`, which checks the pin;
- the **ADR-232 bump writer** `.github/scripts/bump-inngest-bootstrap-pin.sh`, which moves the pin.

Today both take the semver-max over every tag in the repository:

```
git tag --list 'vinngest-v*' | … | sort -V | tail -1
```

This change makes both take the semver-max over tags whose commit is reachable from the checked-out `HEAD`:

```
git tag --merged HEAD --list 'vinngest-v*' | … | sort -V | tail -1
```

In the bump job, `HEAD` is `main`. In PR CI, `HEAD` is the merge ref, which contains `main`.

**The problem it fixes.** A tag cut on an unmerged branch is one that #8747's gate refuses to publish or pin. Today such a tag still becomes the semver-max. That turns AC6 red on `main` and on every open PR, and every legitimate bump below it dies at the `ancestry` stage until someone deletes the tag. After this change an off-main tag is never a candidate, so it has no effect on `main`.

ADR-232 §7, the runbook `inngest-server.md` §Bootstrap-image release, and the C4 edge that describes the bump are all rewritten to say the trap is retired.

**Behavior changes a reviewer should check:**

1. An off-main tag is **excluded** from the candidate set, where before it was **refused** as a target. The #8747 rows that asserted a refusal (B1, B2, B3, B8, B7a) now assert exclusion instead: the pin never moves to the off-main tag, and the registry is never asked about it.
2. The shallow-checkout refusal moves **ahead of** target resolution. Measured on git 2.55: in a shallow clone, `git tag --merged HEAD` exits 0 and silently **drops every tag below the shallow graft**. Tags on `HEAD` itself are still listed. Resolving first could return a lower target and misdiagnose the problem.
3. On a corrupt history, `git tag --merged HEAD` exits **0** with an **empty** list. It reports the damage only on stderr (measured). The existing empty-target refusal (`resolve`) catches this loudly. Its message now names "shallow or unreadable history" as a likely cause.
4. The "legacy off-main pin" refusal (B12) and the "pinned tag deleted" refusal (B13) merge into one downgrade refusal. With `--merged`, a pinned off-main tag can never be the target. It shows up instead as "the pin sorts above the merged max", which is the same state as a deleted pinned tag, and it has the same safe remediation.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue #8782 / parent brief) | Reality (measured 2026-09-27, after `git fetch origin main --tags`) | Plan response |
|---|---|---|
| This is blocked by #8747's post-merge re-anchor. Main's pin must sit on an on-main tag. | **Cleared.** `origin/main` pins `v1.1.40@sha256:5b61557d4477…` at all four sites: `cloud-init.yml` ×2 and `cloud-init-inngest.yml` ×2. `vinngest-v1.1.40` peels to `b8817ff1c4`, the #8775 squash-merge of 2026-09-25. `git merge-base --is-ancestor` confirms that commit is on `origin/main`. | **Proceed.** At merge time, merged-max = overall max = pin = `v1.1.40`. So AC6 stays green and no downgrade PR can be opened. |
| "`--merged` currently resolves to `v1.1.25`" (issue body, 2026-09-24). | It now resolves to `v1.1.40`. 29 tags are merged into `origin/main`. 16 are not: `v1.1.14`, `v1.1.24`, and `v1.1.26` through `v1.1.39`. | **Recorded.** The ADR-232 Alternatives row that rejected `--merged` "now" becomes "adopted 2026-09-27". |
| "Keep the parity assert in sync." | The parity assert (`# Guard 2 row 5: regex parity`) greps literals across both files. A comment can satisfy it, and it cannot see a one-sided edit that keeps each literal somewhere. | **Replace it** with byte-equality of the two shipped selector blocks after normalization (Guard 1 below). The old literal loop is deleted. |
| The shallow refusal lives in `target_on_main`, which runs after resolution. | In a shallow checkout, `--merged` drops tags below the graft with rc 0 (measured). The target then comes out lower than the real max, or empty. | **Move the shallow check ahead of resolution**, still at stage `ancestry` so B9 and B19 keep their stage. Add row B9b: a target tag sitting below the graft. |
| B7 (corrupt history) refuses as "could not decide" via `merge-base` rc 128. | `git tag --merged HEAD` on a history with a missing commit object gives rc 0, empty stdout, and `error: Could not read <sha>` on stderr (measured). | Resolution now fails at `resolve` on the empty target. B7 asserts that stage, plus crane and gh never being called. The `merge-base` call is deleted, because `--merged` already proved ancestry. |
| B7a (commit object of the tag missing) refuses as "tag not found". | A tag whose commit is missing is silently excluded from `--merged` (Kieran measured this on 2.55). | B7a becomes an exclusion row: seed `v1.1.37`, then expect `noop` with `v1.1.38` never consulted. |
| CI checkout depth might need changes. | Every runner of both files already has full history and tags: the `deploy-script-tests` legs in `infra-validation.yml` (`fetch-depth: 0` + `fetch-tags: true`), `main-health-monitor.yml` (same), and the bump job (`ref: main`, `fetch-depth: 0`, `fetch-tags: true`). The bump job's shape is pinned by `g2.bump:fetch-depth`, `g2.bump:fetch-tags` and `g2b.S10`. The fixture suite runs under `pr-quality-guards.yml` → `run-all.sh` and is hermetic. | **No workflow edits.** A shallow CI checkout can only *hide older* tags. So AC6 fails loudly one of two ways: an empty set hits the existing CI FAIL arm, or a lower max shows as DRIFT. It can never go falsely green. |
| C4 is unaffected. | The `model.c4` `github -> soleurMarketplace` edge says "recomputes the target as semver-max vinngest-v*" and "REFUSES … a semver-max target whose commit is not an ancestor of main". Both become false after this change. | Edit the edge prose and regenerate `model.likec4.json`. |
| Predecessor PR #8775. | MERGED 2026-09-25. It closed #8747, not #8782. | Cited as a predecessor only. No collision. |

## Research Insights

**Premise Validation.** All premises checked still hold:

- **Target issue.** #8782 is OPEN with no closing PR.
- **Blocker.** #8747 is CLOSED by PR #8775, MERGED 2026-09-25T00:06Z.
- **Pin.** Main pins `v1.1.40` in both files, and that tag is on `main`.
- **Tag selection.** `git tag --merged origin/main --list 'vinngest-v*' | sort -V | tail -1` returns `vinngest-v1.1.40`, which is also the overall semver-max.
- **Cited anchors.** All exist on `origin/main` (`e3b804196c`):
  - `TARGET=` under `# --- resolve:` in the bump script;
  - `LATEST_TAG=` under `# --- AC6:`;
  - `# Guard 2 row 5: regex parity` in the test suite;
  - `**7. Publish and bump both refuse…` in ADR-232;
  - the "#8782 retires that trap." sentence in the runbook.

**Property List** (Phase 0.6b):

- **P1.** An off-main `vinngest-v*` tag never turns AC6 red on `main`, or on a PR that does not carry the tag's commit.
- **P2.** An off-main tag never blocks a legitimate bump to the highest on-main tag.
- **P3.** The bump never pins an off-main tag. This is the #8747 property, now kept by construction rather than by refusal.
- **P4.** Writer and checker select the same tag for the same checkout. ADR-232 §2 depends on this parity.
- **P5.** Selection is semver, not lexical: `v1.10.0` > `v1.9.0`, and `v1.1.10` > `v1.1.9`. Pre-release and malformed names are never candidates.
- **P6.** A checkout that cannot see full history is refused loudly, never silently mis-selected.
- **P7.** The bump never authors a downgrade, and a pin above every merged tag gets the "do NOT delete it" remediation.

**Cut List.** Each entry names the mechanism, what it would buy, and why it was cut. The later entries were cut at plan-review, where DHH, code-simplicity, Kieran and CTO converged on them.

- **Refusing an off-main *signed* tag in the bump.**
  - P3 already covers this through exclusion.
  - A refusal would break the runbook's legacy `mirror_only` rollback path (B18).
  - The build job already refuses a non-`mirror_only` off-main tag.
- **A shared sourced helper library for the pipeline.**
  - Byte-equality of the two shipped blocks buys P4 more cheaply.
  - A helper would add a cross-tree `source` edge.
  - It would also need a new `infra-validation.yml` `paths:` entry (a workflow edit) and a new `test-affected-paths.sh` mapping.
- **Workflow `fetch-depth`/`fetch-tags` edits.** Already correct on every runner.
- **A `merged_set_decidable` stderr/rc probe.**
  - Corrupt history already fails loudly at `resolve`, whether the list comes back empty or lower.
  - The probe only improved the error text.
  - It would also have been a third match for any census.
- **A signed-tag-not-merged `::notice::`.** `target=<tag>` plus `result=noop` already explain the outcome.
- **Narrowing the crane-failure deferral to `TARGET > SIGNED`, with rows B22/B23.**
  - This was out of scope.
  - Only the deferral wording becomes false, and the wording pass fixes it.
- **An AC6 runtime shallow arm.** Shallow can only produce an empty result (existing CI FAIL arm) or a lower one (DRIFT red), never a false green.
- **The 11-row slice-and-run fixture matrix, `sel_run`, the census row and the old-literal-absent row.**
  - Byte-equality makes the checker's behavior equal to the writer's.
  - The writer's behavior is already exercised by the B rows.
  - Rows S7, S9, S10 and S11 tested git, not this code.
- **Keeping `merge-base --is-ancestor` in `target_on_main`.** `--merged` already proves ancestry, and a tag cannot move "mid-run" inside one local process.
- **The AC scratch-clone mutation check.** It duplicated the fixture suite.

**Relevant files** (anchors, not line numbers):

- `.github/scripts/bump-inngest-bootstrap-pin.sh`
  - header paragraphs "WHY THE TARGET MUST BE ON MAIN" and "WHY THE TARGET IS THE SEMVER-MAX TAG";
  - `# --- resolve:` block (`TARGET=`, `PIN_TAG=`);
  - `target_on_main()`;
  - the downgrade refusal (`Refusing to author a downgrade`);
  - the crane-failure deferral (`deferring to that tag's own publish`);
  - the digest cross-check `::notice::`;
  - `hold_reason`.
- `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`
  - the header bullet;
  - the `# --- AC6:` block: the `LATEST_TAG=` pipeline, the empty-set arms, the `#8747:` diagnostic, and the dedicated-host assert.
- `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh`
  - helpers `base_fixture`, `side_commit`, `precond_*`, `assert_refused`, `run_bump`;
  - rows `g1b.B1`–`g1b.B19`;
  - row `g1.defer`;
  - the `# Guard 2 row 5: regex parity` loop;
  - `MIN_ASSERTIONS=417`.
- `knowledge-base/engineering/architecture/decisions/ADR-232-…md`
  - the Context ¶ "The trigger tag is not the target";
  - §2 and §7;
  - `**Sequencing.**`;
  - the Alternatives row "Target = semver-max over `git tag --merged HEAD` now (#8747)";
  - `## Amendment 2026-09-24 (#8747)` (left verbatim);
  - `## Verification`.
- `knowledge-base/engineering/operations/runbooks/inngest-server.md` §Bootstrap-image release
  - step 1, the "**A tag on a PR-branch commit is refused**" paragraph;
  - step 2, "**Never use it after a failure at stage `ancestry` or `args`**";
  - the sentence "AC6 … asserts pin == the semver-max published".
- `knowledge-base/engineering/architecture/diagrams/model.c4`: the `github -> soleurMarketplace` edge.
- Census and baseline files that mention the AC6 line need **no change**. They are keyed by file or by count, and the edited lines remain one `tag`-verb site with a `|| true` form:
  - `plugins/soleur/test/fixture-dir-operand-assert.baseline.txt` (count `1`);
  - `plugins/soleur/test/fixture-env-adoption.test.sh` DEFERRED entry;
  - `scripts/lint-shell-capture-exit.baseline.txt`.

**Measured git semantics** (git 2.55.0, scratch repos under the session scratchpad):

- **Semver sort.** `printf 'v1.9.0\nv1.10.0\nv1.10.0-rc1\nv1.9.10\n' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1` → `v1.10.0`. Plain `sort` gives `v1.9.0`.
- **Shallow clone.** Setup: depth-1 clone plus `fetch --tags --depth 1`, with tags only on older commits. Result: `git tag --merged HEAD` → empty, rc 0. Kieran confirmed that a tag on `HEAD` is still listed.
- **Missing mid-history commit.** `git tag --merged HEAD` → rc 0, empty stdout, stderr `error: Could not read <sha>` ×2.
- **Tag pointing at a blob.** Excluded, with no stderr. A nested annotated tag (tag of a tag) is peeled and included.

**Institutional learnings applied:**

- `knowledge-base/project/learnings/2026-03-19-git-tag-sort-shallow-clone-semver.md`: shallow clones hide tags on older commits. This motivates the early shallow refusal.
- `knowledge-base/project/learnings/2026-09-25-my-ancestry-gate-was-sound-and-its-harness-and-its-recovery-text-were-not.md`: recovery text must be re-read for truth after a semantic change. This motivates the rewrite of runbook step 2.
- `knowledge-base/project/learnings/2026-03-19-ci-squash-fallback-bypasses-merge-gates.md`: a squash-merge leaves the tagged PR commit unreachable forever. B2 keeps the squash-merged-content exclusion row.

**Conventions:**

- `cq-write-failing-tests-before`
- `cq-cite-content-anchor-not-line-number`
- `hr-when-in-a-worktree-never-read-from-bare`
- `wg-architecture-decision-is-a-plan-deliverable`
- `hr-no-ssh-fallback-in-runbooks`

**External research:** skipped. This is internal git plumbing with strong local precedent, and every git behavior it relies on is measured above.

## Implementation Phases

### Phase 1: RED. Tests first (`.github/scripts/test/test-bump-inngest-bootstrap-pin.sh`)

**1. Replace the literal parity loop** (`# Guard 2 row 5: regex parity`) with **Guard 1: selector byte-equality**.

- **Slice the shipped blocks:**
  - From `$CONSUMER`, start at the line matching `^LATEST_TAG=\$\(git -C "\$SCRIPT_DIR" tag `.
  - From `$SCRIPT`, start at `^TARGET=\$\(git -C "\$REPO_DIR" tag `.
  - Each block ends at the first line matching `\|\| true\)[[:space:]]*$`.
- **Slicer mechanics (Kieran P2):**
  - Pass the start pattern through `ENVIRON`, never `awk -v`, because `-v` processes backslash escapes. Measured: `-v` aborted with "unbalanced (".
  - Shape: `RE='…' awk '$0 ~ ENVIRON["RE"] {on=1} on {print} on && /\|\| true\)[[:space:]]*$/ {exit}' "$f"`.
  - The end pattern cannot match the start line, because the start line ends in `\`.
- **Dispatch rows, per file:**
  - exactly one start line;
  - the slice is exactly 3 lines;
  - the slice contains `tag --merged HEAD --list 'vinngest-v*'` and `sort -V`.
- **The equality row:**
  - Normalize **directionally** (test-design finding 6). Otherwise a checker that used the unset `$REPO_DIR` would pass equality while running `git -C ""` in the current directory.
    - Writer slice: `sed -e 's/^TARGET=/SEL=/' -e 's/"\$REPO_DIR"/"$DIR"/'`.
    - Checker slice: `sed -e 's/^LATEST_TAG=/SEL=/' -e 's/"\$SCRIPT_DIR"/"$DIR"/'`.
  - Strip leading whitespace per line, then `diff`.
  - On a difference, the failure message prints the diff and the fix: "keep the two 3-line `--merged HEAD` selector blocks byte-identical (ADR-232 §2)". This follows CTO's advice that each dispatch row name its fix.
  - Verified on the current tree: the ENVIRON slicer returns exactly 3 lines per file, and the normalized pre-change blocks compare EQUAL. So before Phase 2 only the "contains `--merged HEAD`" dispatch rows go red.
- **Consumer-wiring rows** (these close the former M7 residual; test-design finding 5):
  - `$CONSUMER` has exactly one `LATEST_TAG=` assignment at any indentation. Count it with the slicer's own awk pattern, not a separate grep, so the count and the slice cannot disagree.
  - `grep -cF "[[ '\$PIN' == '\$LATEST_TAG' ]]" "$CONSUMER"` = 1.
  - `grep -cF "[[ '\$DED_PIN' == '\$LATEST_TAG' ]]" "$CONSUMER"` = 1.

**2. Rewrite the #8747 rows whose semantics flip.** The `precond_*` helpers stay, so each fixture still asserts its own precondition.

- **Helper change (test-design finding 4):** `assert_refused <name> <wording> [stage]`, where `stage` defaults to `ancestry`. B7, B12 and B13 pass `resolve`, which replaces their hand-copied refusal asserts. The crane-not-called, gh-not-called and no-bump-branch checks then come for free, including on B13, which D4 relies on.
- **Keep the existing `v1.1.38\t$DIG_NEW` seeds** in B1, B2 and B8. They make a reverted `--list` writer reach `opened` (loud) rather than `skipped`.

- **B1.** Fixture: the off-main semver-max is signed, and the merged max is `v1.1.37`, which is also the pin.
  - Seed `printf 'v1.1.37\t%s\n' "$DIG_OLD" >> "$MOCK_CRANE_MAP"`.
  - Expect:
    - rc 0 and `result=noop`;
    - the output has `target=v1.1.37`;
    - `MOCK_CRANE_LOG` has **no** `v1.1.38`;
    - the origin has no `soleur/inngest-pin-v1.1.38`;
    - `assert_all_pins … v1.1.37 "$DIG_OLD"`;
    - an **empty gh log**;
    - **no `refs/heads/soleur/*` branch at all** on the origin. This is test-design finding 7's strongest extra check: `noop` genuinely requires all four refs to equal `v1.1.37@DIG_OLD`.
- **B2** (squash-merged content): the same explicit `v1.1.37\t$DIG_OLD` seeding (Kieran P1) and the same expectations as B1.
- **B8 is re-shaped** so it still tests the bare-name peel (test-design finding 1, HIGH). Under exclusion, the old shape was only a copy of B1.
  - Put `vinngest-v1.1.38` (annotated) **on main** as the target.
  - Point `refs/vinngest-v1.1.38` at an off-main side commit.
  - Seed `v1.1.38\t$DIG_NEW`.
  - Expect `opened`, `provenance=bound`, and pins at `v1.1.38@$DIG_NEW`.
  - A peel regressed to the bare name `vinngest-${TARGET}^{commit}` resolves the side commit. It then dies at the `SIGNED_COMMIT` binding (stage `ancestry`), turning the row red.
- **B3.** Fixture: on-main signed `v1.1.38` sits below off-main `v1.1.39`.
  - Also run `update-ref refs/remotes/origin/pr-newer <side>` to match the checkout shape.
  - Expect:
    - rc 0 and `result=opened`;
    - `assert_all_pins … v1.1.38 "$DIG_NEW"`;
    - a `gh pr merge .* --auto --squash` call;
    - a crane log with no `v1.1.39`.
  - This is the issue's headline fix: a legitimate bump no longer dies at `ancestry`.
- **B7** (corrupt mid-history):
  - Call `assert_refused 'g1b.B7' 'no vinngest-v* tag is merged into' resolve`.
  - Also require `shallow or unreadable` in the output.
  - **Precondition row** (test-design finding 3): in the fixture, `git tag --merged HEAD --list 'vinngest-v*' 2>/dev/null` prints nothing. The prototype measured an empty result with rc 0 on git 2.55. Another git version that returned a partial list would then red this precondition clearly instead of producing a misleading refusal failure.
- **B7a** (the tag's commit object is gone). Make it an exclusion row:
  - Seed `v1.1.37\t$DIG_OLD`.
  - Expect `result=noop`, with no `v1.1.38` in the crane log.
  - **Precondition row:** `git tag --merged HEAD --list 'vinngest-v*' 2>/dev/null` prints exactly `vinngest-v1.1.37` (measured).
- **B9.** Keep as is.
- **B9b (new).** Fixture:
  - `base_fixture`, then three `main_commit`s;
  - the target `vinngest-v1.1.38` goes on the first main commit (below the graft);
  - then a depth-1 clone plus `fetch --tags --depth 1`;
  - `precondition-shallow`, plus the precondition that `--merged HEAD` **omits** `vinngest-v1.1.38` in the clone.
  - Expect `assert_refused 'g1b.B9b' 'cannot decide which vinngest-v* tags are merged'`.
  - The needle is unique to the moved shallow check (test-design finding 2). The bare word `shallow` also appears in the new `resolve` message, so it would stay green under mutation D1.
  - This row turns red if the shallow check is moved back after resolution. D1 then reddens both the wording row and the stage row.
- **B12** (legacy off-main pin `v1.1.39`, merged tags `{v1.1.25}`), with the unified downgrade refusal:
  - `assert_refused 'g1b.B12' 'Refusing to author a downgrade' resolve`;
  - `Do NOT delete or re-cut` in the output;
  - **no** `git push origin :refs/tags/vinngest-v1.1.39`;
  - add the preconditions: `vinngest-v1.1.39` resolves, and `precond_off_main`.
- **B13** (pinned tag deleted). Switch it to `assert_refused 'g1b.B13' 'Refusing to author a downgrade' resolve` and add a `Do NOT delete or re-cut` row.
  - Per the prototype, its existing six rows already pass. This is added coverage, not a RED driver.
  - Its new crane-not-called row is what makes mutation D4 reachable.
- **All other rows are unchanged:** B4–B6, B10, B10b, B11, B14–B19, `g1.defer`, and every `g1.*` / `g2*` row. Re-run them to confirm.

**3. New bump rows:**

- **B20 (semver order).**
  - The pin is `v1.9.0@$DIG_OLD`. Tags `v1.9.0` and `v1.10.0` are both on main.
  - Signed `v1.10.0`.
  - Seed **both** `v1.9.0\t$DIG_OLD` and `v1.10.0\t$DIG_NEW`. With both seeded, mutation M5 fails legibly as `noop` with `target=v1.9.0`, not as `skipped` (test-design finding 8).
  - Expect `opened`, with pins at `v1.10.0@$DIG_NEW`.
- **B21 (pre-release and malformed names excluded).**
  - The pin is `v1.1.40@$DIG_OLD`. Main carries `v1.1.40`, `v1.2.0-rc1` and `v1.2.0.1`.
  - Signed `v1.1.40`, seeded `v1.1.40\t$DIG_OLD`. The pin digest must equal the seeded one (Kieran P2).
  - Expect `noop`.
  - Assert on the crane log separately for each excluded name: no `v1.2.0-rc1` and no `v1.2.0.1`.

**4. Raise `MIN_ASSERTIONS`** to the green run's exact count after Phase 2.

**5. Expected RED before Phase 2:**

- the Guard 1 dispatch rows (neither slice contains `--merged HEAD` yet);
- B1, B2, B3, B7, B7a, B8, B12 (message and stage changes).

This list is confirmed by the deepen-pass prototype: the unmodified suite against the Phase-2/3.1 script failed exactly these rows plus the `g2.parity` literal row that Guard 1 replaces.

B9b, B13, B20 and B21 already pass on the old code. That is expected: they are ratchets against post-switch mutants, not RED drivers.

### Phase 2: GREEN. Writer (`.github/scripts/bump-inngest-bootstrap-pin.sh`)

1. **Shallow check first.** Place it immediately above `# --- resolve:`, still at stage `ancestry`.
   - Move the block out of `target_on_main`.
   - **Reword it so it does not use `${tag}`/`TARGET`**. Neither is set yet, and under `set -u` the script would abort with no `result=` line (Kieran P1).
   - New wording: `die ancestry "cannot decide which vinngest-v* tags are merged into main: the checkout is shallow (is-shallow-repository='${shallow:-<empty>}') — tags below the graft are invisible to git tag --merged; the bump job needs fetch-depth: 0"`.
   - Keep the rule "refused unless the answer is exactly `false`" (B19).
2. **Resolve.**
   - The pipeline becomes `TARGET=$(git -C "$REPO_DIR" tag --merged HEAD --list 'vinngest-v*' 2>/dev/null \` followed by the unchanged `sed | grep -E | sort -V | tail -1 || true)`. It stays a 3-line block.
   - Update the `# AC6-IDENTICAL PIPELINE` comment so it names Guard 1's byte-equality.
   - New empty-target message: `die resolve "no vinngest-v* tag is merged into HEAD (the ref: main checkout) — nothing can be pinned; if tags exist, the history is shallow or unreadable (git tag --merged reports that only on stderr)"`.
3. **`target_on_main`.**
   - Keep the explicit `refs/tags/vinngest-${TARGET}^{commit}` peel and its `tag not found` die. The name must resolve before the commit binding.
   - Keep the `SIGNED_COMMIT` binding (B10) and `TARGET_COMMIT`.
   - **Delete** the shallow block (it moved), the `merge-base --is-ancestor` call and its rc arms, and the `TARGET == PIN_TAG` legacy arm.
   - Rename the echo to `echo "ancestry: ${tag} (commit ${tag_c}) is merged into main"`.
4. **Unified downgrade refusal.**
   - It already sits before `WORK=$(mktemp -d)`, so crane is still never called on this path.
   - Wording: `die resolve "main pins ${PIN_TAG}, which is above every vinngest-v* tag merged into main (semver-max ${TARGET}) — its tag is either off main (a legacy #8747 pin) or was deleted. Refusing to author a downgrade. Do NOT delete or re-cut the pinned tag. Tag a NEW, higher version on main's latest commit (git tag -a vinngest-vX.Y.Z <main-sha> -m '...' && git push origin vinngest-vX.Y.Z); that tag push runs its own publish and bump."`
   - It stays `error`, not `skipped` (the advisor consult raised this). The state means `main` pins bytes that never merged, so a red job plus Slack is the truthful signal. The prescribed remediation clears it, because a higher tag on `main` makes `TARGET > PIN_TAG`.
5. **Wording pass**, limited to messages this change makes false:
   - The crane-failure deferral `::warning::` and summary currently say "`${TARGET}` is ahead of this run's signed tag". Change to "differs from this run's signed tag `${SIGNED_TAG}` (the target is the semver-max merged tag)". The `g1.defer` needles `::warning::` and `does not self-heal` stay intact.
   - The digest cross-check `::notice::` becomes "(dispatch/mirror_only backfill, or the signed tag is not merged into main)".
   - `hold_reason` for signed ≠ target becomes "this publish signed `${SIGNED_TAG}`, which is not the pin target `${TARGET}`".
   - The header paragraphs become exclusion-by-construction. `--merged HEAD` on the `ref: main` checkout is now the ancestry check. The peel plus commit binding plus revision label bind the pin to a built commit.

### Phase 3: GREEN. Checker (`apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` AC6)

1. **Pipeline.** `LATEST_TAG=$(git -C "$SCRIPT_DIR" tag --merged HEAD --list 'vinngest-v*' 2>/dev/null \`, with the rest of the 3-line block byte-identical to the writer. Guard 1 enforces this.
2. **Empty-set CI arm message.** Add "or a shallow/unreadable history (git tag --merged HEAD cannot see tags below the graft)" beside the existing fetch-depth hint. There is no new arm.
3. **Text.** Assert labels, comments and the header bullet change from "latest published vinngest-v* tag" to "latest vinngest-v* tag merged into HEAD".
4. **Three-way DRIFT diagnostic.** Echo only; the asserts are unchanged.
   - (a) If `vinngest-$LATEST_TAG` is not on `refs/remotes/origin/main`, print the existing `#8747:` delete-the-tag text. This happens only on a PR whose own commit carries the tag.
   - (b) Else, if `PIN` sorts above `LATEST_TAG`, print "pin $PIN is ABOVE every vinngest-v* tag merged into HEAD — its tag is off main or deleted; do NOT bump down to $LATEST_TAG (runbook inngest-server.md §Bootstrap-image release)".
   - (c) Else, print the existing "Fix: bump … to $LATEST_TAG".

### Phase 4: Docs, ADR, C4

**1. ADR-232.** Amend it; the status stays Provisional.

- **Context ¶ "The trigger tag is not the target".**
  - Replace the pipeline with `git tag --merged HEAD --list 'vinngest-v*' | …`.
  - Replace "Since §7 … until #8782 moves both onto tags merged into main." with: writer and checker now agree on both "latest" and "pinnable", and a byte-equality test pins their two selector blocks.
- **§2.** Change to "semver-max `vinngest-v*` **merged into `main`**".
- **§7, first bullet.** Rewrite as exclusion by construction:
  - the shallow refusal runs before resolution;
  - the peel plus `--signed-commit` binding and the revision label still bind the digest to a commit;
  - a pin above every merged tag is refused as a downgrade, with do-not-delete remediation.
- **`**Sequencing.**`** "Switched 2026-09-27 (#8782) after `main` re-anchored on the on-main `v1.1.40` (`b8817ff1c4`)."
- **Alternatives.**
  - Rewrite the `--merged HEAD` "now (#8747)" row to "Adopted 2026-09-27 (#8782); rejected on 2026-09-24 only because it then resolved to `v1.1.25`".
  - Add a row for `--merged origin/main`, rejected for these reasons:
    - The writer's `HEAD` is `main`.
    - In PR CI, a tag on the PR's own commit is visible only on that PR, which is intended: `#8747:` tells the author to delete it.
    - `deploy-script-tests` is advisory.
    - A stale local `origin/main` would mis-select.
    - Keeping one byte-identical pipeline is simpler.
  - Add a row for "refuse an off-main signed tag in the bump": it breaks the legacy `mirror_only` rollback, and the build already refuses such tags.
- **New section `## Amendment 2026-09-27 (#8782)`.**
- **Leave `## Amendment 2026-09-24 (#8747)` verbatim** as a dated record.
- **`## Verification`.**
  - Replace the rows over real git ancestry with the exclusion rows plus B9b, B20 and B21, and Guard 1's byte-equality.
  - Replace the `cloud-init-inngest-bootstrap.test.sh` bullet ("AC6/AC6b/Guard B unchanged") with the AC6 change.

**2. Runbook `inngest-server.md` §Bootstrap-image release.**

- **Step 1, the paragraph "A tag on a PR-branch commit is refused".**
  - "any other bump run that meets the off-main tag dies at stage `ancestry`" becomes: "bump runs ignore it: only tags merged into `main` are candidates".
  - Rewrite "Until an off-main tag is deleted … #8782 retires that trap. A `mirror_only` backfill … ends `result=error` at stage `ancestry` …" to say:
    - Since #8782 (2026-09-27), AC6 and the bump both take the semver-max over tags merged into `main`. So an off-main tag no longer turns `main` or other PRs red and no longer blocks bumps.
    - AC6 stays red only on the PR whose own commit carries the tag.
    - Delete the tag anyway, for hygiene; its name can never be reused.
    - A `mirror_only` backfill of an off-main legacy tag now ends with the bump reconciling to the merged max, normally `result=noop`.
  - Keep the "never delete the tag `main` pins today" exception, reworded to "main pins today", and name the downgrade refusal as its signal.
- **Step 2.** Replace "**Never use it after a failure at stage `ancestry` or `args`**: those refusals mean the tag is off `main`" with a per-stage meaning:
  - `args`: a workflow copy from before #8747.
  - `ancestry`: a shallow checkout, a tag that no longer resolves or was re-pointed after the build, or an image revision label that does not match.
  - `resolve` with "Refusing to author a downgrade": `main` pins a tag that is off main or deleted.
  - A hand-written pin fixes none of these.
- **The AC6 sentence.** "AC6 … asserts pin == the semver-max published `vinngest-v*` tag" becomes "… the semver-max `vinngest-v*` tag merged into `main`".

**3. C4 `model.c4`, edge `github -> soleurMarketplace`.**

- "recomputes the target as semver-max vinngest-v*" becomes "recomputes the target as the semver-max vinngest-v* tag merged into main (git tag --merged HEAD on the ref: main checkout; an off-main tag is never a candidate, #8782)".
- "It REFUSES (stage ancestry, before crane…) a semver-max target whose commit is not an ancestor of main" becomes "It REFUSES (before crane) a shallow checkout and a pin that sits above every merged tag".
- Keep the rest of that clause: the binding, the label and the build-side refusal.
- Regenerate `model.likec4.json` with `bash scripts/regenerate-c4-model.sh`.

### Phase 5: Verify

Run the targeted ratchets in the Acceptance Criteria. Then push and rely on CI:

- the `deploy-script-tests` legs run AC6 against the real tags;
- `pr-quality-guards` runs the fixture suite.

Do not wait for the local full affected gate (per the brief).

## Files to Edit

- `.github/scripts/bump-inngest-bootstrap-pin.sh`
- `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh`
- `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`
- `knowledge-base/engineering/architecture/decisions/ADR-232-inngest-bootstrap-pin-bumps-are-authored-by-the-publish-workflow.md`
- `knowledge-base/engineering/operations/runbooks/inngest-server.md`
- `knowledge-base/engineering/architecture/diagrams/model.c4`
- `knowledge-base/engineering/architecture/diagrams/model.likec4.json` (regenerated, not hand-edited)

## Files to Create

None.

## Open Code-Review Overlap

None. The bodies returned by `gh issue list --label code-review --state open` (up to 200) match none of the paths in Files to Edit.

Separately, open PR #8873 ("fix(inngest-health): select dedicated-host probe rows…") also edits `runbooks/inngest-server.md`, but in a different section, so at most a trivial rebase is needed. It is not a code-review scope-out.

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-232** with `## Amendment 2026-09-27 (#8782)`.

- **Before:** target = semver-max over all tags; an off-main target is refused (§7).
- **After:** target = semver-max over tags merged into `main`; off-main tags are excluded by construction; shallow checkouts and above-merged-max pins are refused.

This amends §2 and §7 and flips one Alternatives row. No new ADR ordinal is needed.

### C4 views

All three files were checked (`model.c4`, `views.c4`, `spec.c4`) against these actors and systems:

- the `github` system, which hosts CI and the App-token write;
- the `ghcr` registry (crane digest read);
- the zot mirror;
- the `soleurMarketplace` edge, which carries the ADR-232 prose;
- the `founder` and `contributor` actors.

No actor, system, container or relationship is added. The **only falsified text** is the `github -> soleurMarketplace` edge description, which Phase 4.3 edits. The `views.c4` NOTE (#8359/ADR-232) describes placement, not selection, so it stays accurate. No cardinality moves; `c4-count-parity.test.sh` is run anyway (AC10).

### Sequencing

None. The decision is true on merge.

## Observability

```yaml
liveness_signal:
  what: "AC6 assert lines 'cloud-init pin (vX) matches latest vinngest-v* tag merged into HEAD (vX)' in deploy-script-tests; bump job terminal 'result=<opened|existing|noop|skipped|error>' plus 'target=<tag> resolved=<digest>' lines"
  cadence: "every PR/merge_group/main push touching the infra suites (deploy-script-tests legs); every vinngest-v* publish (bump-cloud-init-pin job); main-health-monitor scheduled infra run"
  alert_target: "main-health-monitor files ci/main-broken on a red main; bump job failure posts to SLACK_RELEASES_WEBHOOK_URL via its if: failure() step"
  configured_in: ".github/workflows/infra-validation.yml (deploy-script-tests), .github/workflows/build-inngest-bootstrap-image.yml (bump-cloud-init-pin), .github/workflows/main-health-monitor.yml"
error_reporting:
  destination: "GitHub Actions ::error::<stage>: annotations + step summary; Slack #releases on bump failure; ci/main-broken issue via main-health-monitor"
  fail_loud: "stage-named die (ancestry|resolve) with result=error; AC6 FAIL (never SKIP) in CI on an empty merged set"
failure_modes:
  - mode: "CI checkout loses history depth (shallow), so --merged hides tags below the graft"
    detection: "bump: early shallow check dies at stage ancestry 'shallow'; AC6: empty set -> existing CI FAIL arm, lower set -> DRIFT"
    alert_route: "bump -> Slack; deploy-script-tests red -> main-health-monitor ci/main-broken"
  - mode: "corrupt or unreadable history makes git tag --merged exit 0 with an empty list"
    detection: "bump resolve dies 'no vinngest-v* tag is merged … shallow or unreadable'; AC6 CI empty arm"
    alert_route: "Slack (bump); deploy-script-tests red (AC6)"
  - mode: "pin sits above every merged tag (legacy off-main pin or deleted tag)"
    detection: "bump unified downgrade refusal at resolve; AC6 DRIFT with the 'do NOT bump down' diagnostic"
    alert_route: "Slack (bump); deploy-script-tests red (AC6)"
  - mode: "writer and checker selector blocks drift apart"
    detection: "test-bump-inngest-bootstrap-pin.sh Guard 1 byte-equality row"
    alert_route: "pr-quality-guards check red on the PR"
logs:
  where: "GitHub Actions run logs + GITHUB_STEP_SUMMARY for both workflows"
  retention: "GitHub Actions default log retention for the repo (90 days)"
discoverability_test:
  command: "git tag --merged HEAD --list 'vinngest-v*' --sort=-version:refname"
  expected_output: "vinngest-v1.1.40"
```

## Guard Contract

### Guard 1 — writer/checker selector byte-equality (`test-bump-inngest-bootstrap-pin.sh`, replacing `# Guard 2 row 5: regex parity`)

**Property.** For every checkout, AC6 selects the same tag as the bump writer, and that selection is the semver-max well-formed `vinngest-vX.Y.Z` tag merged into `HEAD`. This holds because the two selector blocks are byte-identical after normalizing the variable name and the dir operand. The writer's block is exercised against fixtures by the B rows.

**Assembly.** There are exactly two members, each found by structural slicing rather than by literal grep:

- the `TARGET=$(git -C "$REPO_DIR" tag` block in the writer;
- the `LATEST_TAG=$(git -C "$SCRIPT_DIR" tag` block under `# --- AC6:`.

Both AC6 asserts, on `PIN` and on `DED_PIN`, compare against the single `LATEST_TAG` variable.

A census over `*.sh`/`*.yml` on this branch finds no other `vinngest-v*` latest-tag computation. The census was not made a row, because plan-review cut it as a guard against a hypothetical third selector.

**Mutation matrix.**

| # | Mutation | Must go RED via |
|---|---|---|
| M1 | Checker reverts to `tag --list` (one-sided) | Guard 1 byte-equality row + checker dispatch "contains `--merged HEAD`" |
| M2 | Writer reverts to `tag --list` (one-sided) | Guard 1 byte-equality + writer dispatch row; B1 (pins move to `v1.1.38`), B3 |
| M3 | Both revert together | Both dispatch "contains `--merged HEAD`" rows; B1, B2, B8 |
| M4 | Dispatch: rename `LATEST_TAG=` so the slicer finds no block (guard compares nothing) | Checker dispatch "exactly one start line" |
| M5 | `sort -V` → `sort` in both blocks (equality still holds) | B20 (selects `v1.9.0`) + dispatch "contains `sort -V`" |
| M6 | Regex stage deleted in both blocks | B21 (a pre-release/4-part name becomes the target) |
| M7 | Second member after a compliant first: web assert kept, `DED_PIN` assert compares against a literal | The consumer-wiring row `grep -cF "[[ '\$DED_PIN' == '\$LATEST_TAG' ]]"` = 1 (formerly residual, closed at deepen) |
| M8 | Checker uses the unset `"$REPO_DIR"` (normalization would have hidden it) | Directional normalization: the checker slice keeps `$REPO_DIR`, so the equality row goes red |

**Harness rows.**

- *Suite edit that must go red:* the slicer's end pattern changes so it prints only the first line. The "exactly 3 lines" dispatch row then goes red, and the byte-equality row can no longer pass on two truncated slices.
- *Must-PASS input that is not the canonical:* the real files differ in LHS name (`TARGET` vs `LATEST_TAG`) and in dir operand (`$REPO_DIR` vs `$SCRIPT_DIR`). The normalization must accept exactly those differences, so a green equality row over the real, differing text is itself the must-pass.

**Anchor.** Consistency only. A single PR can edit both blocks and the suite, and all three are visible in one review diff.

### Guard 2 — bump exclusion + history visibility + no downgrade (`bump-inngest-bootstrap-pin.sh`)

**Property.** The bump never pins a tag whose commit is not reachable from the `main` checkout. It never pins below the current pin. It refuses (with crane never called) any checkout whose history is shallow, and any state whose merged set is empty.

**Assembly.** These code paths run in order, all before `WORK=$(mktemp -d)` and the first `crane` call:

1. the early shallow check;
2. the `TARGET=` resolve plus the empty-target die;
3. `target_on_main` (peel + `SIGNED_COMMIT` binding);
4. the unified downgrade refusal.

The only write surface, the `sed -i` rewrite, runs strictly after all four.

**Mutation matrix.**

| # | Mutation | Must go RED via |
|---|---|---|
| D1 | Move the shallow check back after resolution | B9b: target silently lower or empty → stage `resolve`, and the unique needle `cannot decide which vinngest-v* tags are merged` is absent |
| D7 | Peel regresses to the bare name `vinngest-${TARGET}^{commit}` | B8 (re-shaped): the shadow ref resolves the side commit → the `SIGNED_COMMIT` binding dies |
| D2 | Drop `--merged HEAD` from the writer | B1/B2/B8 (pins move to the off-main tag), B3 |
| D3 | Delete the downgrade refusal | B12/B13 (a downgrade PR is opened) |
| D4 | Move the downgrade refusal after the crane loop | B12/B13 `crane-not-called` rows |
| D5 | Delete the `SIGNED_COMMIT` binding | B10 |
| D6 | Downgrade message regains a `git push origin :refs/tags/…` delete command | B12 `no-delete-command` row |

**Harness rows.**

- *Suite edit that must go red:* `run_bump` stops prepending `--signed-commit`. Every row past `args` then goes red at `args`, which proves the rows exercise the later stages.
- *Must-PASS input that is not the canonical:* B18. A legacy off-main *signed* backfill below an on-main target is still `opened`. An over-correction that refuses off-main signed tags would turn it red.

**Anchor.** Consistency only; one PR edits both the script and the suite. The runtime backstop outside the commit is Slack plus `main-health-monitor`.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly. The pin selects the image that a **fresh or replaced** Inngest host boots, and host replace is dispatch-only. A wrong selection would surface in one of two ways:

- (a) AC6 turns red on `main` and on PRs, which is CI noise visible to developers;
- (b) a bump PR opens against a wrong tag.

After this change only on-main tags are candidates, a strict subset of what was allowed before. The downgrade refusal blocks moving below the current pin.

**If this leaks, the user's workflow is exposed via:** no path. The change reads git tags and history and writes nothing new. The existing App-token push path is unchanged.

**Brand-survival threshold:** none

- threshold: none, reason: the diff touches `apps/web-platform/infra/` only in a CI test file (AC6), and it narrows the bump's candidate set to reviewed on-`main` commits. No runtime, host, credential or data surface changes, and this PR redeploys nothing.

## Acceptance Criteria

- [ ] **AC1.** The writer resolves `TARGET` with `git -C "$REPO_DIR" tag --merged HEAD --list 'vinngest-v*' 2>/dev/null`, followed by the unchanged `sed | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1 || true` stages.
  - `grep -c "tag --merged HEAD --list 'vinngest-v\*'" .github/scripts/bump-inngest-bootstrap-pin.sh` = 1.
  - The shallow check's `rev-parse --is-shallow-repository` line precedes the `TARGET=` line. Verify with `grep -n` ordering.
- [ ] **AC2.** AC6 uses the identical block on `git -C "$SCRIPT_DIR"`. Guard 1's byte-equality row is green. `grep -c "tag --merged HEAD --list 'vinngest-v\*'" apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` = 1.
- [ ] **AC3.** `bash .github/scripts/test/test-bump-inngest-bootstrap-pin.sh` ends `Results: <N> pass, 0 fail`, and `MIN_ASSERTIONS` is raised to exactly `<N>`.
  - The run includes the Guard 1 dispatch and equality rows.
  - It includes every pre-existing `g1.*`/`g1b.*`/`g2*`/`g2b.*` row, with the Phase 1 rewrites to B1, B2, B3, B7, B7a, B8, B12 and B13.
  - It includes the new B9b, B20 and B21.
  - The old `g2.parity:*` literal rows are gone: `grep -c "g2.parity:" <suite>` = 0.
- [ ] **AC4.** The PR body records one line of RED-first evidence: the FAIL lines from the suite run on the Phase-1-only commit.
- [ ] **AC5.** Selection on the real repo is unchanged at merge:
  - `git tag --merged origin/main --list 'vinngest-v*' | sed 's/^vinngest-//' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1` prints `v1.1.40`.
  - `git show origin/main:apps/web-platform/infra/cloud-init.yml | grep -oE 'soleur-inngest-bootstrap:v[0-9.]+' | sort -u` prints `soleur-inngest-bootstrap:v1.1.40`. The same holds for `cloud-init-inngest.yml`.
  - So AC6 is green, and no downgrade PR is possible.
- [ ] **AC6.** The gate's own invocation, run the way `scripts/test-all.sh` runs it (`run_suite "scripts/lint-shell-capture-exit-live"`), exits 0: `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`. Also `bash plugins/soleur/test/fixture-dir-operand-assert.test.sh` and `bash plugins/soleur/test/fixture-env-adoption.test.sh` pass unchanged.
- [ ] **AC7.** ADR-232 checks (against the ADR file):
  - `grep -c '^## Amendment 2026-09-27 (#8782)'` = 1.
  - `grep -c "git tag --merged HEAD --list 'vinngest-v\*'"` ≥ 1.
  - `grep -cE 'until #8782 (moves both|switches the bump)'` = 0.
  - The dated `## Amendment 2026-09-24 (#8747)` section is byte-unchanged.
  - The Alternatives table carries the adopted `--merged HEAD` row, plus the `origin/main`-anchor row and the refuse-off-main-signed-tag row.
- [ ] **AC8.** Runbook checks (against `knowledge-base/engineering/operations/runbooks/inngest-server.md`):
  - `grep -c '#8782 retires that trap'` = 0.
  - `grep -c 'tags merged into `main`'` ≥ 1.
  - `grep -c 'those refusals mean the tag is off `main`'` = 0.
  - `git diff origin/main...HEAD -- knowledge-base/engineering/operations/runbooks/inngest-server.md | grep '^+' | grep -ci 'ssh '` = 0.
- [ ] **AC9.** C4 checks:
  - The `github -> soleurMarketplace` edge no longer contains `a semver-max target whose commit is not an ancestor of main`.
  - `bash scripts/regenerate-c4-model.sh` has been run.
  - `bash plugins/soleur/test/c4-model-freshness.test.sh` and `bash plugins/soleur/test/c4-count-parity.test.sh` pass.
  - `(cd apps/web-platform && npx vitest run test/c4-code-syntax.test.ts test/c4-render.test.ts)` passes. The runner comes from `apps/web-platform/package.json` `"test": "vitest"`.
- [ ] **AC10.** `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-09-27-ci-vinngest-semver-max-merged-into-main-plan.md` exits 0.
- [ ] **AC11.** CI: `deploy-script-tests` (all legs) and `pr-quality-guards` are green on the PR. `git diff --name-only origin/main...HEAD -- .github/workflows` is empty.
- [ ] **AC12.** The first line of the PR body reads: "Merging this alone mutates no production state: no pin moves (main already pins the merged-max `v1.1.40`), no Terraform/`paths:`-triggered apply fires, and the new selection first runs on the next `vinngest-v*` publish."

## Domain Review

**Domains relevant:** none

No cross-domain implications were detected. This is an infrastructure/tooling change: CI tag selection, its tests, and the ADR, runbook and C4 text that describe them.

- No UI surface: no path in Files to Edit matches the UI term list.
- No regulated data.
- No new vendor or cost.

The plan-review named panel ran the CTO devex lens. Its findings were folded in or recorded in `decision-challenges.md`.

## Test Scenarios

By property:

- **P1/P2:** B3 (a legitimate bump below an off-main max is `opened`). The PR-own-tag case is intended AC6-red-on-that-PR-only behavior, documented in the ADR Alternatives.
- **P3:** B1, B2, B7a, B8. The off-main tag is never pinned and never resolved via crane.
- **P4:** Guard 1 byte-equality, plus the writer's B rows.
- **P5:** B20, B21.
- **P6:** B7, B9, B9b, B19.
- **P7:** B12, B13, plus the AC6 three-way diagnostic.
- **Legacy backfill:** B18. **Deferral (unchanged path):** `g1.defer`.

## Risks

- **A semantics flip on existing rows could be misread as weakening them.** B1, B2 and B8 change from `error` to `noop`. *Mitigation:* each rewritten row asserts a stronger invariant: the off-main tag never reaches crane, never gets a branch, and the pin never moves. The PR body lists the flip.
- **On a PR that carries a tag on its own commit,** `--merged HEAD` still sees that tag, so AC6 goes red on *that* PR only. This is intended. The `#8747:` diagnostic tells the author to delete the tag. `deploy-script-tests` is advisory and not in any ruleset (`git grep deploy-script-tests -- infra/github/` finds nothing).
- **Local stale branches:** AC6 now compares a branch's pin with that branch's own merged max. This removes false reds on branches that forked before a newer tag existed.
- **Merge conflict** with open PR #8873 in `inngest-server.md` (a different section): a trivial rebase.

## Non-Goals

- GHCR retirement (ADR-096 5.3–5.5), live host replaces, and the legal cluster (per the brief).
- The missing ancestry check in `deploy-inngest-image.yml`, tracked as #8780 (ADR-232 Residuals).
- Deleting the 16 legacy off-main tags. They are the rollback path, and the runbook keeps them.
- Sub-cause tokens on `ancestry` messages. This CTO devex suggestion is recorded in `decision-challenges.md`.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, holds only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. That section is filled in above.
- **`git tag --merged` fails open.** It exits 0 while silently omitting tags below a shallow graft, and omitting every tag on a corrupt walk. Any future caller must check `--is-shallow-repository` first and must treat an empty result as a refusal, never as "nothing to do".
- **Nothing that runs before resolution may reference `TARGET` or `${tag}`,** because the script runs under `set -u` (Kieran P1).
- **Keep both selector blocks at three lines, ending `|| true)`.** Guard 1's slicer and its equality row depend on that shape by design, and the failure message names the fix.
- **Pass the slicer pattern through `ENVIRON`, not `awk -v`.** `-v` processes backslash escapes and breaks the regex.
