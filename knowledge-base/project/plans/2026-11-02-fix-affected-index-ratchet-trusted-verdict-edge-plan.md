---
title: "fix: declare trusted-verdict edge for scripts/inngest-a5-a6-owner-ask-10136 (affected-index ratchet, #11897)"
type: fix
date: 2026-11-02
slug: fix-affected-index-ratchet-trusted-verdict-edge
branch: feat-one-shot-11897-declare-trusted-verdict-edge
issue: 11897
closes: 11897
lane: cross-domain
priority: medium
domain: engineering/ci
brand_survival_threshold: none
---

# fix: declare trusted-verdict edge for scripts/inngest-a5-a6-owner-ask-10136

Spec lacks valid `lane:` (no spec.md on this branch) — defaulted to `cross-domain` (TR2 fail-closed).

## Overview

The advisory `affected-index-ratchet` job is red on main with exactly one residual `new-pair`:
suite `scripts/inngest-a5-a6-owner-ask-10136` names `scripts/lib/trusted-verdict.sh` at
`scripts/followthroughs/inngest-a5-a6-owner-ask-10136.test.sh:739` (anchor `b3c6682aadf9`,
ordinal 1). That line is a fixture write into a `$FORCED` scratch tree — but the pair is judged
at suite level, and the suite really executes `scripts/lib/trusted-verdict.sh`: the probe it
runs sources `$libdir/trusted-verdict.sh` at
`scripts/followthroughs/inngest-a5-a6-owner-ask-10136.sh:177`, and the test header documents
"the real trusted-verdict lib therefore runs unmodified". The remedy is therefore a **declared
edge** — an `AFFECTED_SCRIPTS_INNGEST_A5_A6_OWNER_ASK_10136_PATHS` array in
`scripts/lib/test-affected-paths.sh` — never an accept row: an accept row on a file the suite
really reads is a false negative the moment the lib changes, and no automated control checks the
claim.

This is the last live pair on main (`live=1511 baseline=1510` before the change; `live=1510`
after it, verified in a scratch worktree), so landing it greens the ratchet and closes #11897.

## Research Insights

**Premise Validation (Phase 0.6) — every brief claim verified on this tree:**

| Brief claim | Verified | Evidence |
|---|---|---|
| Issue #11897 open | yes | `gh issue view 11897` → `state: OPEN`, label `meta/machinery`; umbrella for the post-#11766 residual pairs |
| Exactly one new-pair | yes | `python3 -I scripts/ci-pr-affected-replay.py ratchet` → exit 1, `SOLEUR_PR_AFFECTED_RATCHET exit=1 reason=new-pair live=1511 baseline=1510`, one `new-pair` row |
| Pair identity + anchor | yes | ratchet `ref` line: `...test.sh:739 b3c6682aadf9/1` — `printf 'exit %s\n' "$forced_rc" > "$FORCED/scripts/lib/trusted-verdict.sh"` |
| Fixture write into `$FORCED` scratch | yes | test.sh:733-743 — `assert_fixture_dir "$FORCED"`, `cp` the probe + relayed lib, `printf` the stub trusted-verdict, loop `forced_rc in 0 1 7` |
| Probe sources real lib at `.sh:177` | yes | `source "$libdir/trusted-verdict.sh"` guarded by `declare -F trusted_verdict_bodies` (.sh:176-179); relayed at :181-184 |
| Header documents real lib | yes | test.sh:8 — "The real trusted-verdict lib therefore runs unmodified" |
| Array name via label map | yes | `lint-orphan-test-suites.sh:1139` derives `AFFECTED_$(label uppercased, non-alnum→_, leading _ dropped)_PATHS` → `AFFECTED_SCRIPTS_INNGEST_A5_A6_OWNER_ASK_10136_PATHS`; no such array exists today |
| Current row `edge:derived`, covers only own files + relayed-verdict | yes | `--print-selection --paths=scripts/lib/trusted-verdict.sh` → `sel=0`, edges `^test.sh|^.sh|^relayed-verdict.sh` |
| Declared unions with derived | yes | post-edit scratch row → `sel=1 edge:declared ^test.sh|^.sh|^relayed-verdict.sh|^trusted-verdict.sh|^test-affected-paths.sh` |

**Declare-vs-accept evidence (pre-acceptance grep per
`ci-pr-affected-activation.md` §Ratchet red and the 2026-11-02 learning "issue-prescribed ratchet
remedy can be wrong"):** grepping the suite for the basename `trusted-verdict` finds three
mentions (header comment, the `$FORCED` write at :739, and the grep-pin at :797-799 asserting the
probe calls `trusted_verdict_bodies "$EPIC"`); grepping for the parent dir `scripts/lib/` finds
only the relayed-verdict `cp` (:737, already derived) and the `$FORCED` write. The real
read/execute edge lives in the **SUT source** — `source "$libdir/trusted-verdict.sh"`, a computed
path the audit's literal scan cannot mint. Per the 2026-11-01 learning ("ratchet repair: … the
SUT-source boundary line decides declare-vs-accept"), a SUT runtime read makes the pair a declared
edge even when the only visible boundary line is a fixture mention. Registration comment at
`scripts/test-all.sh:6247-6249` already documents the design: "drives the 7-row decision table
through a gh shim and the REAL trusted-verdict and relayed-verdict libs".

**End-to-end proof (scratch worktree `/tmp/aff-reveal-11897`, detached at HEAD):** applying the
candidate array below and running `ratchet --root` → `exit=0 reason=pass live=1510 baseline=1510`;
`--print-selection --paths=scripts/lib/trusted-verdict.sh` → `sel=1 edge:declared`. **Zero
reveal:** the lib names four tracked paths in comments (:56-57 basenames, :150
`scripts/lib/git-data-boot-signal-poll.sh`) and none mints a pair — no accept rows needed.

**Property List (Phase 0.6b):**

- P1: a diff touching `scripts/lib/trusted-verdict.sh` selects `scripts/inngest-a5-a6-owner-ask-10136` (the suite that exercises the lib).
- P2: the ratchet on main returns to `exit=0 reason=pass` — no `new-pair`, nothing revealed.
- P3: no accept row is consumed for a file the suite really executes (no future false negative).

**Cut List:** none. The ask names exactly one mechanism (the declared-edge array, the index's own
remediation channel); no repo mechanism already covers the pair — the derive demonstrably misses
it (`edge:derived` does not reach `trusted-verdict.sh`).

**Institutional learnings applied:**

- `2026-11-01-ratchet-repair-pair-disposition-moved-echoes-and-sut-source-boundary` — ran `audit --all-refs`; the pair's ONLY boundary line is test.sh:739 (single ref, nothing hidden by the 3-ref cap).
- `2026-11-02-issue-prescribed-ratchet-remedy-can-be-wrong` — ran the pre-acceptance grep; verified the remedy against code, not the issue text.
- `2026-10-26-a-ratchet-green-on-the-branch-tip-was-red-on-the-merged-tree` — ACs are expressed against the merged-tree check (`ratchet` on this branch == main-tip semantics since this branch is `origin/main` + empty init commit; CI runs the merge SHA).

**Relevant file paths:**

- `scripts/lib/test-affected-paths.sh` — the index; new array goes immediately after `AFFECTED_SCRIPTS_INNGEST_PROBE_HEARTBEAT_FEEDER_PATHS` (line ~3332), beside the `scripts/inngest-*` sibling and ahead of `AFFECTED_SCRIPTS_BETTERSTACK_INCIDENT_MIRROR_PATHS`.
- `scripts/test-all.sh:6250` — `run_suite "scripts/inngest-a5-a6-owner-ask-10136" bash scripts/followthroughs/inngest-a5-a6-owner-ask-10136.test.sh` (the label the array name derives from).
- `scripts/lint-orphan-test-suites.sh:1139` — the label→array-name derivation the census enforces.
- Sibling conventions: `AFFECTED_SCRIPTS_FOLLOWTHROUGHS_DISPATCH_RECOVERY_SWEEPER_11211_PATHS` (:723), `AFFECTED_SCRIPTS_FOLLOWTHROUGHS_INNGEST_LUKS_KEEPER_DARK_11265_PATHS` (:734), `AFFECTED_SCRIPTS_INNGEST_PROBE_HEARTBEAT_FEEDER_PATHS` (:3324) — suite `.sh` + `.test.sh` + real deps + `scripts/lib/test-affected-paths.sh` self-inclusion, with a comment naming the reads derivation cannot reach.

## Files to Edit

- `scripts/lib/test-affected-paths.sh` — insert one array block after `AFFECTED_SCRIPTS_INNGEST_PROBE_HEARTBEAT_FEEDER_PATHS` (closing `)` at line 3332):

```bash
# scripts/inngest-a5-a6-owner-ask-10136 — the #11218 owner-ask probe suite execs the REAL
# trusted-verdict lib through its SUT: the probe sources $libdir/trusted-verdict.sh
# (scripts/followthroughs/inngest-a5-a6-owner-ask-10136.sh:177), a computed path no derivation
# channel reaches; the test header pins "the real trusted-verdict lib therefore runs
# unmodified". Derivation reaches relayed-verdict.sh via the $REPO_ROOT cp literal (:737) but
# the only trusted-verdict literal is the $FORCED scratch write (:739).
AFFECTED_SCRIPTS_INNGEST_A5_A6_OWNER_ASK_10136_PATHS=(
  "scripts/followthroughs/inngest-a5-a6-owner-ask-10136.sh"
  "scripts/followthroughs/inngest-a5-a6-owner-ask-10136.test.sh"
  "scripts/lib/trusted-verdict.sh"
  "scripts/lib/relayed-verdict.sh"
  "scripts/lib/test-affected-paths.sh"
)
```

`relayed-verdict.sh` is already derived today but is a real dep of the suite — listing it matches
the sibling convention of naming every real dependency the selector must know, and keeps the edge
if the derive's literal scan narrows. Ordering matches siblings: suite files, real deps, THIS
FILE last. (The scratch verification used the same member set; member order is not significant.)

## Files to Create

None (pipeline artifacts — this plan, `tasks.md`, `decision-challenges.md` — are knowledge-base
records, not change surface).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly — this is internal CI
  machinery (`meta/machinery`). The failure mode is a missed suite selection: a future edit to
  `scripts/lib/trusted-verdict.sh` could merge without running the one suite that executes it,
  silently degrading the followthrough probes' trust-verdict behavior.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no exposure — a
  repo-relative path list in a test-selection index; the file is already public in the repo.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** internal-only advisory CI signal with no user-facing
  surface; the next tier (`single-user incident`) would require a user-visible artifact, which
  this diff cannot produce.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "add `AFFECTED_SCRIPTS_INNGEST_A5_A6_OWNER_ASK_10136_PATHS` to `scripts/lib/test-affected-paths.sh`" [brief] | Files-to-Edit entry / Phase 1 | mapped |
| 2 | "the remedy is a DECLARED edge, not an accept row (an accept row would be a false negative when the lib changes)" [brief] | Phase 1 content: no accept.tsv edit | mapped |
| 3 | "Verify post-edit that the ratchet exits 0 and the suite's selector row covers the lib" [brief] | AC1, AC2, Test Scenarios | mapped |
| 4 | "Follow the file's conventions: sibling followthroughs arrays list the suite's .sh + .test.sh + real deps + `scripts/lib/test-affected-paths.sh` self-inclusion" [brief] | Files-to-Edit array members | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| New `AFFECTED_SCRIPTS_INNGEST_A5_A6_OWNER_ASK_10136_PATHS` array in `scripts/lib/test-affected-paths.sh` | "add `AFFECTED_SCRIPTS_INNGEST_A5_A6_OWNER_ASK_10136_PATHS` to `scripts/lib/test-affected-paths.sh`" | asked |
| `relayed-verdict.sh` as array member | "the suite's .sh + .test.sh + real deps + `scripts/lib/test-affected-paths.sh` self-inclusion" | asked |
| Ratchet + selector verification ACs | "Verify post-edit that the ratchet exits 0 and the suite's selector row covers the lib" | asked |
| Suite + census-lint verification ACs | — | inferred — justification: `lint-orphan-test-suites.sh` censuses every `AFFECTED_*_PATHS` member and the suite itself is the SUT the edge protects; both are the cheapest guards that the declaration is well-formed |

### Split Assessment

- Subsystems touched: 1 — `scripts/`
- Planned files: 1 | Estimated changed lines: ~13
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] `python3 -I scripts/ci-pr-affected-replay.py ratchet` exits 0 and prints `SOLEUR_PR_AFFECTED_RATCHET exit=0 reason=pass` on this branch (verified pre-landing in a detached scratch worktree: `live=1510 baseline=1510`).
- [ ] `bash scripts/test-all.sh --print-selection --paths=scripts/lib/trusted-verdict.sh` prints a row `AFFECTED_SELECTED\tscripts/inngest-a5-a6-owner-ask-10136\t1\tedge:declared` whose edge list contains `^scripts/lib/trusted-verdict.sh`.
- [ ] `git diff --quiet origin/main...HEAD -- scripts/ci-pr-affected-audit.accept.tsv scripts/ci-pr-affected-audit.baseline.tsv` exits 0 (no accept row, no baseline edit — the ratchet's own remedies forbid a baseline row; merge-base triple-dot, not the moving tip).
- [ ] `bash scripts/lint-orphan-test-suites.sh` exits 0 (the new array's name derives from the registration label and every member is a tracked path).
- [ ] `bash scripts/followthroughs/inngest-a5-a6-owner-ask-10136.test.sh` exits 0 (the suite the edge protects still passes).
- [ ] `git diff --name-only origin/main...HEAD` lists only `scripts/lib/test-affected-paths.sh` plus this pipeline's own artifacts under `knowledge-base/project/plans/` and `knowledge-base/project/specs/feat-one-shot-11897-declare-trusted-verdict-edge/` — no other product file.

## Test Scenarios

- Given the declaration lands, when a diff touches `scripts/lib/trusted-verdict.sh`, then
  `--print-selection --paths=scripts/lib/trusted-verdict.sh` reports
  `scripts/inngest-a5-a6-owner-ask-10136` selected with reason `edge:declared`. (integration —
  deterministic command, verified once at work time in the scratch worktree and re-verified on
  the real diff)
- Given the declaration lands, when `ratchet` runs on the branch, then it prints
  `exit=0 reason=pass` with `live=1510 baseline=1510`. (integration)
- Given a suite member were mistyped, when `lint-orphan-test-suites.sh` censuses the array, then
  it exits non-zero — so the green census is a well-formedness check on the new block. (integration)
- Given the `$FORCED` fixture arm (:733-743), when the suite runs, then it still substitutes the
  stub lib and passes — the declared edge changes selection only, never suite behavior. (unit —
  covered by the suite's own run)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal CI/test-selection machinery (`meta/machinery`).

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` bodies contain no mention of
`scripts/lib/test-affected-paths.sh` or `scripts/followthroughs/inngest-a5-a6-owner-ask-10136`.

## Context

- **Consumer of the new list (sharp edge: a selection-list entry must name its reader):**
  `_affected_classify` in `scripts/test-all.sh` maps the registration label to the array name
  and resolves it — `scripts/test-all.sh:3962-3965`:

  ```bash
  _arr="AFFECTED_${_u}_PATHS"
  if declare -p "$_arr" >/dev/null 2>&1; then
    _affected_resolve_edges "$_arr"
    _AC_CLASS="edge:declared"
  ```

  `_u` is the label uppercased with non-alphanumerics → `_` and one leading `_` dropped
  (inline at :3959-3961, byte-identical to `_aff_label_map` at :2799-2804 and to the census at
  `lint-orphan-test-suites.sh:1139`). Declared edges then **union** with derived at
  :3968-3979 (`_decl` buffered, `_affected_derive` runs, declared re-added through
  `_affected_add_declared_edge` at :3325) — verified live: the scratch selector row reads
  `edge:declared` with `^trusted-verdict.sh` beside the three derived edges.
- **Oracle-input edit:** `scripts/lib/test-affected-paths.sh` is one of the ratchet's oracle
  inputs. On this PR the index pre-pass (`_aff_classify_runner_diff`, G5 binding at
  `scripts/test-all.sh:2997-3018`) sees an `AFFECTED_*_PATHS` block added for a label this diff
  did NOT register → `INDEX-UNBOUND` → `runner-changed` → the local `--affected` gate and the
  PR's own run take the full battery once. Expected, not a defect — the index file's header
  documents exactly this arm. A CODEOWNERS entry routes review but the repo ruleset requires
  none, so the reviewer must check the declare-vs-accept claim by reading the suite — the
  evidence table above is written for that read.
- **Why not an accept row:** the accept remedy is for "a message, a fixture it writes into a
  scratch tree, a negative-test string". Boundary line :739 IS a scratch write, but the *pair* is
  suite-level and the suite executes the real lib — per the drain rubric, "(a) executes or
  sources the file … a computed path … counts".
- **Why no reveal:** declaring makes the audit read `trusted-verdict.sh`; it names four tracked
  paths in comments and none formed a pair in the scratch run (`live=1510` after the edit).
- **Collision check:** `collision-precheck.sh 11897` → PR #11919 is this branch's own draft; PR
  #11867 (`feat-prod-readiness-gap-analysis`) names the issue only incidentally — no live
  duplicate.
- **Skipped gates (with reasons):** Observability — Files-to-Edit is `scripts/lib/` at repo root,
  outside the gate's trigger roots (`apps/*/server|src|infra`, `plugins/*/scripts`), and the
  change's signal IS the advisory CI job it feeds; Guard Contract — the deliverable declares data
  for an existing guard, it creates no guard/gate/lint; ADR/C4 — no architectural decision, the
  edge applies the index's existing contract; Encryption Posture — no store or connection;
  Task Design — no new autonomous-task surface; GDPR — no regulated-data surface.

## References

- Related issue: #11897 (umbrella; last residual pair — this change greens the ratchet), #11881 (dup-accept fix), #11766 (pair source), #11218 (suite's issue)
- Runbook: `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` §Ratchet red — the two-remedy decision + drain rubric
- Learnings: `knowledge-base/project/learnings/test-failures/2026-11-01-ratchet-repair-pair-disposition-moved-echoes-and-sut-source-boundary.md`, `knowledge-base/project/learnings/workflow-patterns/2026-11-02-issue-prescribed-ratchet-remedy-can-be-wrong.md`
- Verification scratch: `/tmp/aff-reveal-11897` (detached worktree; removed after planning)

## Implementation Phases

1. **Declare the edge.** Apply the `Files to Edit` block to `scripts/lib/test-affected-paths.sh`
   after `AFFECTED_SCRIPTS_INNGEST_PROBE_HEARTBEAT_FEEDER_PATHS` (line 3332).
2. **Verify.** Run the AC commands: `ratchet` → exit 0 `reason=pass`; `--print-selection
   --paths=scripts/lib/trusted-verdict.sh` → `sel=1 edge:declared`; `lint-orphan-test-suites.sh` →
   exit 0; the suite `inngest-a5-a6-owner-ask-10136.test.sh` → exit 0; `git status` shows only the
   index file plus pipeline artifacts changed.
