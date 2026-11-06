---
title: "fix(ci): declare refresh-stage-a.test.sh's real-read edges in the affected index"
type: fix
date: 2026-11-06
slug: affected-index-refresh-stage-a-edge
branch: feat-one-shot-10865-constraint-scaffold-pairs
issue: 10865
lane: cross-domain
---

# fix(ci): declare refresh-stage-a.test.sh's real-read edges in the affected index (Ref #10865)

## Overview

The advisory affected-index ratchet paused the #10865 observation window when #12177
(04fc68d782) landed 11 undeclared `constraint-scaffold` pairs. #12166 (cffdf2705a, in this
branch's base) already dispositioned all 11 as mentions via accept rows 609-654 of
`scripts/ci-pr-affected-audit.accept.tsv`. The remaining gap — the actual work of this
slice — is that `plugins/soleur/skills/constraint-scaffold/test/refresh-stage-a.test.sh`
has **no** `AFFECTED_*_PATHS` block: it runs on `edge:derived` edges that cannot see its
real inputs (composed `$REAL_SCRIPTS`/`$REAL_REFS`/`$OLD_FIXTURE` vars), so a change to
the SUT (`constraint-scaffold.sh`), its template, its ledger, or its pinned fixture does
not select the suite — a silent skip once `CI_PR_AFFECTED` goes live.

The fix is one new declared-edge block in `scripts/lib/test-affected-paths.sh` (after the
parity block at ~line 2422) plus whatever accept rows the ratchet fixpoint reveals for
the two derived `apps/web-platform/` entries the declared block replaces (fixture-write
mentions, never real reads — the suite header itself states "the real apps/web-platform
tree is never touched", refresh-stage-a.test.sh:8).

**Held scope:** the #10859 required-context flip surfaces (`required-checks.txt`,
canonical ruleset JSON, `infra/github`, count pins, `CI_PR_AFFECTED`) are NOT touched —
the flip stays held for the budget owner.

Spec lacks valid `lane:` (no spec.md on this branch) — defaulted to cross-domain (TR2 fail-closed).

## User-Brand Impact

- **If this lands broken, the user experiences:** a constraint-scaffold SUT/template/fixture change that silently skips `refresh-stage-a.test.sh` in the affected gate, so a regression in the `--refresh-stage-a` pin-refresh path ships green — the operator's CI gate reports a pass it did not earn.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no exposure vector — the diff is test-index metadata (edge declarations + accept rows); no user data, secrets, or runtime surface is read or written.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the change is CI-selection metadata whose worst case is a wrong suite-selection set on a still-advisory check; no user-facing surface is reachable.

## Research Insights

**Premise Validation.** `gh issue view` confirms #10865 OPEN (soak tracker) and #10859 OPEN
(required-flip, held). #12166 and #12177 are MERGED. **Stale premise corrected:** the brief
described #12212 as an *open* sibling owning the two live foreign pairs; it MERGED at
2026-11-06T07:52:55Z (511db9f84f, +11 lines in `scripts/lib/test-affected-paths.sh` only).
This branch is 2 commits behind `origin/main` (`511db9f84f` #12212, `4e0f90b56c` #12149);
the ratchet run here still reports `live=2` for the two foreign pairs only because the
declarations that cover them are not in our base — **a rebase clears them without any work
in this diff** (verified: `git merge-base --is-ancestor 511db9f84f HEAD` → false; ratchet
`--base origin/main` → `exit=1 reason=new-pair live=2 baseline=0`, both pairs foreign).
Collision precheck (`collision-precheck.sh 10865`): the only open PR naming #10865 is this
branch's own draft #12217; a foreign worktree `feat-one-shot-bun-pair-ratchet-accept-cleanup`
has `test-all.sh` running — sibling ratchet/accept work in flight, so `accept.tsv` is a
rebase-collision surface to re-verify after each sync.

**Current state (verified on this tree).**

- `scripts/test-all.sh --print-selection --paths=plugins/soleur/skills/constraint-scaffold/scripts/constraint-scaffold.sh` → row for `plugins/soleur/skills/constraint-scaffold/test/refresh-stage-a.test.sh`: `0 edge:derived` with edges `^plugins/soleur/skills/constraint-scaffold/test/refresh-stage-a.test.sh`, `^plugins/soleur/test/lib/git-fixture-env.sh`, `^apps/web-platform/.github/workflows/constraint-gates.yml`, `^apps/web-platform/scripts/constraint-gates.sh`. The suite IS registered (the row exists), so a complete declared block is index-bound and legal.
- The suite's real repo-side inputs (verified by reading the suite):
  - `plugins/soleur/skills/constraint-scaffold/scripts/` — `cp -R`'d into per-case sandboxes (:142), SUT executed `bash $sd/constraint-scaffold.sh --refresh-stage-a` (:148, :350), grepped at :382-384. `REAL_SCRIPTS="$SKILL/scripts"` (:23).
  - `plugins/soleur/skills/constraint-scaffold/references/` — `cp -R`'d (:142, `REAL_REFS="$SKILL/references"` :24); template read at :110, :158, :283-285, :389-394; ledger `fix-constraints-stage-a.emitted.sha256` read at :266, :288, :301, :382, :385-386.
  - `plugins/soleur/skills/constraint-scaffold/test/fixtures/stage-a.v1.0.236.emitted` — `OLD_FIXTURE` (:25), `cp`'d (:133, :236, :315) and `cmp`'d via `same_bytes` throughout.
  - `plugins/soleur/test/lib/git-fixture-env.sh` — sourced at :96.
- The two derived `apps/web-platform/` edges are **mentions, not reads**: `:129` and `:368` name `apps/web-platform/scripts/constraint-gates.sh` only as fixture writes inside scratch `$BASE`/`$FX` repos; `constraint-gates.yml`/`fix-constraints-stage-b.yml` are reached only via composed `$WF_DIR_REL` paths (:27, :131-132, :216, :368). Once the declared block replaces derived edges these will surface as flagged pairs → accept rows (mention class), anchor/ordinal taken from the ratchet's `ref` lines. Expect ~2-4 new accept rows; likely pairs: `apps/web-platform/scripts/constraint-gates.sh` (anchors at :129 and :368) and possibly `apps/web-platform/.github/workflows/constraint-gates.yml` / `fix-constraints-stage-b.yml` / the `apps/web-platform/.github/workflows` dir literal (:27) if the audit resolves composition.
- Sibling block convention (scripts/lib/test-affected-paths.sh:2378-2422):
  `AFFECTED_PLUGINS_SOLEUR_SKILLS_CONSTRAINT_SCAFFOLD_TEST_<NAME>_TEST_SH_PATHS` arrays list
  SUT/inputs + suite self + `scripts/lib/test-affected-paths.sh` + `scripts/test-all.sh`.
  Dir-honest entries (`references/`, `apps/web-platform/`, `.github/`) are already used by
  neighbors — parity block uses `plugins/soleur/skills/constraint-scaffold/references/`.
- Accept-row format: `suite<TAB>path<TAB>anchor<TAB>ordinal<TAB>false-positive: <reason>`;
  suite key is the suite file path (`plugins/soleur/skills/constraint-scaffold/test/refresh-stage-a.test.sh`), anchors are 12-hex of the mention line; rows sorted by suite+path live at ~609-654 for this suite.

**Learning applied:** `knowledge-base/project/learnings/2026-10-26-a-ratchet-green-on-the-branch-tip-was-red-on-the-merged-tree.md`
— anchor-keyed accept rows and edge declarations must be verified on the *merged* tree, not
the branch tip: rebase/merge `origin/main` FIRST, then declare, then verify the ratchet
again (and via `git merge-tree` scratch check before arming).

**Property List (Phase 0.6b).** (a) A change to the SUT, its `scripts/`/`references/` dirs, or
the pinned fixture selects `refresh-stage-a.test.sh` — no silent skip. (b) Fixture-name
mentions stay un-selected (accept rows, not edges). (c) The ratchet reaches `exit=0 live=0`
on the merged tree. Existing mechanisms covering these: the `AFFECTED_*_PATHS` declared-edge
mechanism + `accept.tsv` mention exemption — no new machinery proposed.

**Cut List.** None — the ask names the exact mechanism (edge block + accept rows); both
properties are bought by mechanisms already on `origin/main`.

**Gate assessments (all evaluated, all skip):** 1.5 community discovery — no stack gap;
1.5b functional-overlap / Phase 1 research fan-out / 4.5 advisor consult — analysis already
complete and verified on-tree per the one-shot brief; no spawn tool in this pipeline seat
(decisions recorded `pending - assumed` in `decision-challenges.md`); 2.7 GDPR — no
regulated-data surface, no (a)-(d) trigger; 2.8 IaC — no infrastructure; 2.9 Observability —
Files-to-Edit match none of `apps/*/server|src|infra`, `plugins/*/scripts` (the touched files
are `scripts/lib/` + a TSV data file; preflight Check 10 is also SKIP since no sensitive path
is touched); 2.9.3 task-design — no new workflow/cron/registered check; 2.10 ADR/C4 — no
architectural decision (data repair inside the existing ADR-242 mechanism); 2.11 encryption —
no store/connection; 2.12 Guard Contract — no NEW guard authored: the diff feeds data to the
existing affected-index mechanism whose guard (ratchet+audit) already exists.

## Files to Edit

- `scripts/lib/test-affected-paths.sh` — insert one block after the parity block
  (`AFFECTED_PLUGINS_SOLEUR_SKILLS_CONSTRAINT_SCAFFOLD_TEST_PARITY_TEST_SH_PATHS` ends ~line
  2422, before the git-worktree block):

  ```bash
  # plugins/soleur/skills/constraint-scaffold/test/refresh-stage-a.test.sh — derived edges could not reach its subject; declared from the
  # repo paths its suite file names.
  AFFECTED_PLUGINS_SOLEUR_SKILLS_CONSTRAINT_SCAFFOLD_TEST_REFRESH_STAGE_A_TEST_SH_PATHS=(
    "plugins/soleur/skills/constraint-scaffold/references/"
    "plugins/soleur/skills/constraint-scaffold/scripts/"
    "plugins/soleur/skills/constraint-scaffold/test/fixtures/"
    "plugins/soleur/skills/constraint-scaffold/test/refresh-stage-a.test.sh"
    "plugins/soleur/test/lib/git-fixture-env.sh"
    "scripts/lib/test-affected-paths.sh"
    "scripts/test-all.sh"
  )
  ```

  Dir entries are deliberate: the suite `cp -R`s `scripts/` and `references/` wholesale into
  sandboxes (:142) and `$OLD_FIXTURE` lives under `test/fixtures/` — every file under each
  dir feeds the verdict. `git-fixture-env.sh` is carried over from the derived edge set
  (sourced at :96). `apps/web-platform/` paths are deliberately ABSENT — fixture mentions,
  not reads (suite :8).
- `scripts/ci-pr-affected-audit.accept.tsv` — append the anchor-keyed accept rows the
  ratchet fixpoint flags for the dropped derived `apps/web-platform/` edges (mention class:
  "fixture file/path written into the scratch `$BASE`/`$FX` repo (refresh-stage-a.test.sh:<anchor-line>); never the repo file"). Insert in sorted position beside the
  existing refresh-stage-a rows (~609-654). Zero new rows is a legal fixpoint only if the
  ratchet flags nothing after the block lands — verify, do not assume.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-10865-constraint-scaffold-pairs/decision-challenges.md` — decision-class table (pipeline artifact).

## Implementation Phases

### Phase 1 — Sync base (rebase onto origin/main)

1. `git fetch origin && git rebase origin/main`. Expected clean: #12212's hunks land at
   ~1261 and ~4814, ours at ~2422 (non-adjacent); #12149's accept.tsv row at ~1953 vs ours
   at ~630 (non-adjacent). On conflict: accept.tsv is a union (additions only — check `0
   removed` vs origin/main); test-affected-paths.sh take both blocks.
2. Re-run `python3 -I scripts/ci-pr-affected-replay.py ratchet --base origin/main` — the two
   foreign pairs MUST be gone (covered by #12212's declarations now in base). If they persist
   post-rebase, STOP and re-triage — do not duplicate their declarations.

### Phase 2 — Declare the edge block

Insert the `AFFECTED_..._REFRESH_STAGE_A_TEST_SH_PATHS` block above at the anchor (~line
2422). `bash -n scripts/lib/test-affected-paths.sh`.

### Phase 3 — Ratchet fixpoint

`python3 -I scripts/ci-pr-affected-replay.py ratchet --base origin/main`; for each `new-pair`
flagged on `refresh-stage-a.test.sh`, add the accept row keyed to the `ref` line's
anchor/ordinal. Repeat until the suite contributes zero live pairs. Cap: if the fixpoint
exceeds ~6 new rows or flags a pair that is a REAL read, stop and re-classify — the
classification (mention vs read) is the load-bearing decision, per the remedy text's
false-negative warning.

### Phase 4 — Verify on merged tree

- `bash scripts/test-all.sh --print-selection --paths=<input>` for EACH real input
  (`plugins/soleur/skills/constraint-scaffold/scripts/constraint-scaffold.sh`,
  `.../references/fix-constraints-stage-a.template`,
  `.../references/fix-constraints-stage-a.emitted.sha256`,
  `.../test/fixtures/stage-a.v1.0.236.emitted`,
  `plugins/soleur/test/lib/git-fixture-env.sh`) → the suite row shows `1` selected with
  `edge:declared`.
- `--paths=apps/web-platform/scripts/constraint-gates.sh` → suite NOT selected (`0`).
- `bash -n` on both edited files; run `scripts/test-all-affected.test.sh` and
  `scripts/test-affected-kb-consumers.test.sh`.
- Merged-tree check per the 2026-10-26 learning: `git merge-tree` scratch (or the Phase-1
  rebase result) then ratchet once more immediately before arming — and again after every
  sibling merge while queued (the bun-pair sibling worktree is live on the same files).

### Phase 5 — Post-merge deliverable

After the PR merges: `gh issue comment 10865` recording — the drained 11-pair class (all
mentions, dispositioned on main by #12166), the INDEX-UNBOUND edge this PR declared, the
live=2 remainder having been owned by merged #12212, and the resulting ratchet state.
Do NOT flip any #10859 surface.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Classify-then-dispose all 11 (mention → accept row per anchor/ordinal in scripts/ci-pr-affected-audit.accept.tsv; real read → AFFECTED_*_PATHS edge block in scripts/lib/test-affected-paths.sh)" | Phase 2 edge block + Phase 3 fixpoint accept rows; 11-pair class verified already dispositioned by #12166 | mapped |
| 2 | "a complete block is legal but must name every verdict-relevant path incl. SUT + self + THIS FILE" | Phase 2 block contents (SUT via `scripts/` dir, self, `scripts/lib/test-affected-paths.sh`) | mapped |
| 3 | "Verify ratchet exit=0 live=0, then post the repair status to #10865" | Phase 4 verification + Phase 5 `gh issue comment` | mapped |
| 4 | "Do NOT touch the #10859 flip surfaces (required-checks.txt, canonical ruleset JSON, infra/github, count pins, CI_PR_AFFECTED)" | Held-scope line in Overview; no such file in Files-to-Edit | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `scripts/lib/test-affected-paths.sh` edge block | "real read → AFFECTED_*_PATHS edge block in scripts/lib/test-affected-paths.sh" | asked |
| `accept.tsv` fixpoint rows | "mention → accept row per anchor/ordinal in scripts/ci-pr-affected-audit.accept.tsv" + "Re-run the ratchet to a fixpoint after the block lands" (established-state note) | asked |
| Phase 1 rebase | — | inferred — justification: #12212 merged after branch cut; the ratchet remedy line says "rebase, then declare", and the 2026-10-26 learning requires merged-tree verification for anchor-keyed artifacts |
| `decision-challenges.md` | "Persist every decision as a row of the \| Item \| Class \| Ruling \| table in knowledge-base/project/specs/<branch>/decision-challenges.md" (technical-rulings brief) | asked |
| Phase 5 issue comment | "post the repair status to #10865" | asked |

### Split Assessment

- Subsystems touched: 1 — `scripts/` (plus 1 KB spec artifact)
- Planned files: 3 | Estimated changed lines: ~15-40
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1: `AFFECTED_PLUGINS_SOLEUR_SKILLS_CONSTRAINT_SCAFFOLD_TEST_REFRESH_STAGE_A_TEST_SH_PATHS` exists in `scripts/lib/test-affected-paths.sh` naming `plugins/soleur/skills/constraint-scaffold/scripts/`, `.../references/`, `.../test/fixtures/`, the suite file itself, `plugins/soleur/test/lib/git-fixture-env.sh`, `scripts/lib/test-affected-paths.sh`, `scripts/test-all.sh`.
- [ ] AC2: `bash scripts/test-all.sh --print-selection --paths=plugins/soleur/skills/constraint-scaffold/scripts/constraint-scaffold.sh` reports the suite `1` selected with `edge:declared`; same for the template, ledger, fixture, and git-fixture-env inputs.
- [ ] AC3: `python3 -I scripts/ci-pr-affected-replay.py ratchet --base origin/main` exits `0` with `live=0` on the rebased tree (foreign pairs cleared by the rebase, suite pairs drained by block+accept rows).
- [ ] AC4: `bash scripts/test-all.sh --print-selection --paths=apps/web-platform/scripts/constraint-gates.sh` does NOT select `refresh-stage-a.test.sh` (mention correctly un-declared), and every flagged pair along the way has an accept row keyed to its `ref` anchor/ordinal.
- [ ] AC5: `bash -n` clean on edited files; `scripts/test-all-affected.test.sh` and `scripts/test-affected-kb-consumers.test.sh` pass.
- [ ] AC6: No diff line touches `required-checks.txt`, ruleset JSON, `infra/github`, count pins, or `CI_PR_AFFECTED` (#10859 hold).
- [ ] AC7 (post-merge): issue #10865 carries a status comment recording the drained 11-pair class, the declared INDEX-UNBOUND edge, and the live=2 remainder's ownership by merged #12212.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — CI test-index metadata change.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` (200) searched for
`scripts/lib/test-affected-paths.sh`, `scripts/ci-pr-affected-audit.accept.tsv`, and
`plugins/soleur/skills/constraint-scaffold/test/refresh-stage-a.test.sh`: zero matches.

## Out of Scope

- The #10859 required-context flip (held for budget owner).
- The 11 `constraint-scaffold` mention pairs — already dispositioned on main by #12166.
- The two foreign live pairs — owned and declared by merged #12212; resolved here by rebase only.
- Any change to `refresh-stage-a.test.sh` itself, the SUT, or the ratchet/audit machinery.
