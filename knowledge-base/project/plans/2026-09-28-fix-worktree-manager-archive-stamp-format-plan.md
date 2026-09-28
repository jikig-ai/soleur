---
title: "machinery: align worktree-manager archive stamp to compact YYYYMMDD-HHMMSS"
type: fix
date: 2026-09-28
slug: fix-worktree-manager-archive-stamp-format
branch: feat-one-shot-9091-archive-stamp-format
issue: 9091
closes: 9091
lane: cross-domain
---

# machinery: align worktree-manager archive stamp to compact YYYYMMDD-HHMMSS

## Enhancement Summary

**Deepened on:** 2026-09-28
**Sections enhanced:** Research Insights (verification evidence), Proposed Solution (precedent
+ adjacent-divergence note), References
**Research agents used:** sequential inline equivalents of repo-research-analyst,
learnings-researcher, code-simplicity / correctness / test-design / pattern-recognition /
security / architecture lenses (no subagent spawn surface in this harness — one-shot pipeline).

### Key Improvements (deepen-pass verifications)

1. **Two-producers claim verified repo-wide:** the only `mv`-into-`archive/` producers under
   `plugins/soleur/` scripts and `.claude/hooks/` are `worktree-manager.sh:2485` (inside
   `archive_kb_files`) and `worktree-manager.sh:3337` (spec-archive block) — plus `archive-kb.sh`
   itself, already compact. No third producer exists.
2. **"Nothing parses the stamp" held with a nuance:** literal full-path citations to existing
   archive entries exist (`scripts/generate-article-30-register.sh:17`,
   `scripts/followthroughs/plugin-delivery-canary-7490.sh:34`, docs/README references) — they
   name existing entries verbatim, never parse the stamp shape, so the format change cannot
   break them. `generate-kb-index` excludes `*/archive/*` by path segment regardless of stamp.
3. **No SKILL.md documents the stamp format** (`git-worktree`/`archive-kb` SKILL.md say
   "timestamp prefixes" format-agnostically) — no doc edits required; Files-to-Edit list is
   complete.
4. **PR/issue citations verified live:** #9091 OPEN; #9087 MERGED (`chore(archive-kb): archive
   the #9035 spec dir`); #8493 MERGED (the #8490 fix); #8418 MERGED (`fix(8400,8401,8402)` —
   provenance of the suite this plan extends). Rule id `cq-test-fixtures-synthesized-only`
   verified ACTIVE in `AGENTS.md`.
5. **Precedent-diff (Phase 4.4):** the stamp format's precedent is `archive-kb.sh:171`; the
   test-extension's precedent is the suite's own A3 must-PASS arm + `assert_fixture_dir`/
   `mk_repo`/`mk_merged_branch` helpers — no novel pattern.
6. **Portability:** `date +%Y%m%d-%H%M%S` uses only POSIX format codes — identical on GNU and
   BSD/macOS `date`; no `-d`, `stat -c`, or `readlink -f` class risk (Sharp Edges line 4).

### New Considerations Discovered

- **Adjacent divergence (recorded, not in scope):** `archive-kb.sh` moves artifacts via
  `git mv` (SKILL.md: "uses `git mv` to preserve history") while `archive_kb_files` uses a bare
  `mv`. Same class of producer-level divergence as this issue but orthogonal to the stamp
  format; deliberately left out of scope — candidate for a future machinery issue if it recurs.
- **Discoverability probe constraint:** the `discoverability_test.command` was rewritten during
  plan review to satisfy preflight Check 10's byte-level shell-active reject (no `|`, `;`,
  `&`, `<`, `>`, `$`, backtick) — the final form is a single `grep -c` producing a literal `2`.

## Overview

Issue #9091 (surfaced during the PR #9087 review) records a cosmetic divergence in the
knowledge-base archive naming produced by two Soleur scripts.
`plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` stamps the spec directories it
archives during `cleanup-merged` reaps with `date +%Y-%m-%d-%H%M%S` (dashed), while
`plugins/soleur/skills/archive-kb/scripts/archive-kb.sh` stamps the same class of artifact with
`date +%Y%m%d-%H%M%S` (compact). The compact shape dominates the archive siblings (481/532 in
`specs/archive`, including all recent entries); the dashed shape keeps being reintroduced by the
reaper. Nothing parses the stamp — `generate-kb-index.sh` excludes `*/archive/*` by path segment —
so the consequence is broken prefix uniformity and C-locale sort order only. The fix aligns both
worktree-manager stamp sites to the compact format and adds a stamp-format assertion to the
manager's cleanup-merged test.

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Codebase reality | Plan response |
|---|---|---|
| #9091: "worktree-manager stamps spec-archive dirs `date +%Y-%m-%d-%H%M%S` … ~1-line fix" | Two dashed name-stamp sites exist: `worktree-manager.sh:3333` (spec dirs) **and** `worktree-manager.sh:2484` (`archive_kb_files`, minting dashed names in `plans/archive` + `brainstorms/archive`) | Fix both sites (+1 line over the literal ask); the property the issue names — prefix uniformity vs. compact siblings — applies to all three archive namespaces |
| #9091: "476/528 specs/archive siblings use compact" | Measured on this branch: 481/532 compact in `specs/archive`; `plans/archive` 439/483, `brainstorms/archive` 122/140 compact (all dashed rows are legacy + reaper output) | Forward-only convergence; no backfill rename |

## Problem Statement / Motivation

Two producers write timestamped names into the same archive namespaces:

- `worktree-manager.sh` (`cleanup_merged_worktrees` reap path) names spec-archive dirs
  `<stamp>-<safe_branch>` with `date +%Y-%m-%d-%H%M%S` at `worktree-manager.sh:3333`, and names
  brainstorm/plan archive files `<stamp>-<fname>` with the same dashed format inside
  `archive_kb_files` at `worktree-manager.sh:2484`.
- `archive-kb.sh:171` stamps `TIMESTAMP=$(date +%Y%m%d-%H%M%S)` (compact) for the same
  `<dir>/archive/<stamp>-<name>` target shape.

Measured populations on this branch (C-locale `ls` census):

| Directory | stamped entries | dashed `YYYY-MM-DD-…` | compact `YYYYMMDD-…` |
|---|---|---|---|
| `knowledge-base/project/specs/archive` | 532 | 51 | 481 |
| `knowledge-base/project/plans/archive` | 483 | 44 | 439 |
| `knowledge-base/project/brainstorms/archive` | 140 | 18 | 122 |

The dashed rows are legacy plus fresh reaper output (the issue notes `2026-09-27-205027-…` was
normalized by hand in PR #9087). Every reap keeps adding dashed names while every `archive-kb`
run adds compact ones, so the divergence is live, not historical.

## Proposed Solution

1. In `worktree-manager.sh`, change the format literal at both stamp sites from
   `+%Y-%m-%d-%H%M%S` to `+%Y%m%d-%H%M%S`:
   - `archive_name="$(date +%Y-%m-%d-%H%M%S)-$safe_branch"` (`worktree-manager.sh:3333`,
     spec-archive dir name).
   - `ts="$(date +%Y-%m-%d-%H%M%S)"` (`worktree-manager.sh:2484`, inside `archive_kb_files`,
     covering `brainstorms/archive` and `plans/archive` entries — the only callers are
     `worktree-manager.sh:3349-3350`).
2. Add a stamp-format assertion to
   `plugins/soleur/test/worktree-manager-cleanup-merged-no-worktree.test.sh` — the suite that
   already drives `cleanup_merged_worktrees` end-to-end on synthesized repos via `run_reaper`.
   Extend a must-PASS reap arm (A3) with a `knowledge-base/project/specs/<branch>` fixture dir
   and a `knowledge-base/project/plans/*<slug>*` fixture file, then assert each produced
   `archive/` basename matches `^[0-9]{8}-[0-9]{6}-`. One reap exercises both stamp sites.

**Scope decision (recorded):** the issue's literal text names only the spec-archive stamp ("~1
line"), but `archive_kb_files` produces the same dashed names in `plans/archive` and
`brainstorms/archive` — the identical property violation, one more one-line edit. The plan fixes
both sites; the alternative (spec-only) is recorded under Alternatives Considered.

**Forward-only:** no rename/backfill of the 51+44+18 existing dashed entries. They are archive
records nothing consumes; rewriting them churns git history for zero functional gain.

## Alternatives Considered

| Option | Disposition |
|---|---|
| Align only `worktree-manager.sh:3333` (literal issue text) | Rejected — leaves `archive_kb_files` minting dashed names in `plans/archive` + `brainstorms/archive` on every reap; the property the issue names (prefix uniformity, C-locale sort) stays violated in two of three namespaces for +1 line of savings |
| Shared stamp lib used by both scripts | Cut at Phase 0.6b — `archive-kb.sh` sources no lib today and `worktree-manager.sh` sources only `session-state.sh`/`tmp-classify.sh` for unrelated concerns; a new shared helper to carry one `date` format buys nothing the two-literal edit doesn't (Property List P1 already covered) |
| Align archive-kb to dashed instead ("vice-versa" in the issue) | Rejected — compact is the dominant population (≈90% of siblings, 100% of September entries); converging on the minority format manufactures more divergence |
| Rename existing dashed entries for uniformity | Rejected — history churn on archive records; nothing parses the stamp; forward-only convergence |

## Files to Edit

- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` — two `date` format literals
  (anchor `archive_kb_files`'s `ts=` inside the `for f in "$dir"/*"$slug"*` loop, ~line 2484;
  anchor `archive_name=` inside the spec-archive block of `cleanup_merged_worktrees`,
  ~line 3333).
- `plugins/soleur/test/worktree-manager-cleanup-merged-no-worktree.test.sh` — extend the A3
  must-PASS arm (or add an adjacent arm) with the `knowledge-base/` fixture + basename-regex
  assertions; follow the file's existing conventions (`assert_fixture_dir`, per-row
  `pass`/`fail`, `MIN_ASSERTIONS` floor remains satisfied — it is a floor, not an exact count).

## Files to Create

None.

## Research Insights

**Premise Validation (Phase 0.6).** Issue #9091 is OPEN, not closed by any PR
(`gh issue view 9091 --json state,closedByPullRequestsReferences`). Both cited files and line
anchors verified: `worktree-manager.sh:3333` (spec stamp, dashed) and `archive-kb.sh:171`
(compact). **Enrichment:** the issue says "stamps spec-archive dirs … ~1-line fix", but a full
`date +` census of worktree-manager.sh found a *second* dashed name-stamp site at
`worktree-manager.sh:2484` (`archive_kb_files`, used for `brainstorms/` + `plans/` at lines
3349–3350). The remaining `date` sites (lines 351, 2796, 2812, 3224, 3260) produce epoch
seconds, not names — out of scope. Nothing else in the repo reads the stamp shape
(repo-wide grep for `%Y-%m-%d-%H%M%S` / archive-name parsing returned no consumers;
`generate-kb-index` excludes `*/archive/*` by path segment). No ADR governs archive-name
format.

**Property List (Phase 0.6b).**

- P1: every archive entry worktree-manager names carries the same compact `YYYYMMDD-HHMMSS-`
  prefix that archive-kb produces, so new entries sort uniformly with the dominant sibling
  population in all three archive namespaces.
- P2: a produced-name assertion exists so the format cannot silently regress (the defect
  re-entered via the reaper precisely because nothing asserted it).

**Cut List (Phase 0.6b).**

- Shared stamp lib → buys P1 → the two-literal edit already buys P1 (`archive-kb.sh` sources no
  lib; verified by grep). Cut.
- Existing-dashed-entry backfill → buys no property the issue names (cosmetic forward
  uniformity); cut.

**Relevant learnings.**

- `knowledge-base/project/learnings/2026-09-20-every-defect-in-my-fix-was-a-sentence-i-could-have-run.md`
  — provenance of the cleanup-merged suite this plan extends; its conventions (must-PASS
  non-canonical arms, landing assertions, floor-not-exact-count) apply to the new rows.
- `knowledge-base/project/learnings/2026-05-04-plan-precedent-search-must-include-lib-helpers.md`
  — lib helpers were grepped before rejecting the shared-lib option.
- `knowledge-base/project/learnings/2026-03-13-bash-arithmetic-and-test-sourcing-patterns.md`
  — bash test-sourcing conventions for the plugin suites.

**Conventions.** `cq-test-fixtures-synthesized-only` — the knowledge-base fixture dirs/files are
synthesized under the suite's `$TMP` repo, never copied from the live tree. The suite's
git-location tripwire and `fgit`/`git_fixture_env` helpers are reused unchanged.

**Lane note.** No `spec.md` exists yet for this branch — `lane:` defaulted to `cross-domain`
(TR2 fail-closed).

## User-Brand Impact

- **If this lands broken, the user experiences:** a wrongly-named archive directory or file under
  `knowledge-base/project/{specs,plans,brainstorms}/archive/` — in the worst shape a failed `mv`
  that leaves a spec dir unarchived (a warn-line the script already emits), not data loss.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no exposure vector —
  the change renames local archive paths; no data leaves the repo, no credential surface is
  touched.
- **Brand-survival threshold:** `none`

## Observability

```yaml
liveness_signal:
  what: "stamp-format assertion rows in worktree-manager-cleanup-merged-no-worktree.test.sh"
  cadence: "per local suite run / per CI run of the plugin bash suites"
  alert_target: "operator terminal and CI job log"
  configured_in: "plugins/soleur/test/worktree-manager-cleanup-merged-no-worktree.test.sh"
error_reporting:
  destination: "suite stdout/stderr (FAIL rows) — the script itself already warns on a failed mv"
  fail_loud: "a FAIL row plus nonzero suite exit when a produced archive basename misses ^[0-9]{8}-[0-9]{6}-"
failure_modes:
  - mode: "stamp format reverts to dashed at either site (regression)"
    detection: "the two new assertion rows go RED on the produced basenames"
    alert_route: "local test output; CI failure where the bash suite runs"
  - mode: "archive step silently stops producing entries (no spec dir / failed mv)"
    detection: "existence-required assertion on the produced archive entry goes RED"
    alert_route: "local test output; suite's existing warn-path in worktree-manager.sh"
logs:
  where: "suite log capture per arm ($TMP/*.log) and operator terminal"
  retention: "ephemeral per run"
discoverability_test:
  command: grep -c '%Y%m%d-%H%M%S' plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh
  expected_output: "2"
```

## Guard Contract

### Guard 1 — cleanup-merged archive stamp-format assertion

**Property.** Every archive entry `worktree-manager.sh` names during a reap — spec dirs and
brainstorm/plan files — begins with a compact `YYYYMMDD-HHMMSS-` prefix, matching the format
`archive-kb.sh` produces.

**Assembly.** Exactly two stamp sites produce archive names in this script:
`archive_name=` at `worktree-manager.sh:3333` (feeds `mv "$spec_dir" "$archive_path"`) and
`ts=` at `worktree-manager.sh:2484` inside `archive_kb_files` (feeds
`mv "$f" "$archive_dir/$ts-$fname"`, called for `brainstorms/` and `plans/` at lines 3349–3350).
The assertion's real assembly is the set of produced basenames under
`<clone>/knowledge-base/project/{specs,plans}/archive/` in the fixture; a third archive-name
producer does not exist (verified by the `date +` census + `mv` audit of the reap path — epoch
`date +%s` sites are not names).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Revert `archive_name=` (~line 3333) to `+%Y-%m-%d-%H%M%S` | produced spec-archive dir fails the compact basename regex → RED |
| 2 | Revert `archive_kb_files` `ts=` (~line 2484) to `+%Y-%m-%d-%H%M%S` | produced plans/archive entry fails the regex → RED — the check must not stop at the first (spec-dir) member |
| 3 | Make the archive step unreachable (force `[[ -d "$spec_dir" ]]` false) | the assertion requires the produced entry to exist → RED (dispatch row: a guard over an artifact never produced is vacuous) |
| 4 | Harness: drop the `specs/<branch>` fixture dir but keep the assertion | RED — existence is asserted, not only shape |
| 5 | Harness must-PASS, non-canonical: plans-file fixture only, no spec dir | reap still produces a compact-stamped plans/archive entry → PASS (property holds without the canonical member) |

**Anchor.** The assertion compares produced names to a format literal in the same commit as the
SUT; the outside anchor is the independent producer `archive-kb.sh:171`
(`date +%Y%m%d-%H%M%S`) plus the measured sibling population (481/532 compact in
`specs/archive`). A weakening that kept both consistent would have to edit across two skills.

## Acceptance Criteria

- [ ] `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` contains zero remaining
  `date +%Y-%m-%d-%H%M%S` literals (both stamp sites use `date +%Y%m%d-%H%M%S`).
- [ ] `plugins/soleur/skills/archive-kb/scripts/archive-kb.sh` is unchanged.
- [ ] `plugins/soleur/test/worktree-manager-cleanup-merged-no-worktree.test.sh` asserts the
  basename of a produced `specs/archive/` entry AND a produced `plans/archive` (or
  `brainstorms/archive`) entry each match `^[0-9]{8}-[0-9]{6}-`, with existence required (not a
  vacuous pass on an absent entry).
- [ ] `bash plugins/soleur/test/worktree-manager-cleanup-merged-no-worktree.test.sh` exits 0
  locally; `MIN_ASSERTIONS` floor still satisfied.
- [ ] No existing archive entry is renamed (forward-only convergence).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal tooling/machinery change to a plugin bash
script and its test. No UI-surface file paths in Files to Edit/Create, so the mechanical
override did not fire; Product/UX Gate tier is NONE.

## Test Scenarios

- Given a merged, unleased branch with `knowledge-base/project/specs/<branch>/` present in the
  clone, when `cleanup-merged` reaps it, then `specs/archive/` contains exactly one new dir named
  `<8 digits>-<6 digits>-<safe_branch>`.
- Given the same reap and a `knowledge-base/project/plans/*<slug>*` file (slug = branch minus
  `feat-` prefix), when the reap runs, then `plans/archive/` contains
  `<8 digits>-<6 digits>-<filename>` matching the same regex — this row covers the
  `archive_kb_files` site, not only the spec site.
- Given no spec dir (harness mutation row 4), when the suite's assertion still requires the
  produced entry, then the row goes RED — proving existence is asserted.
- Edge case: two reaped branches in the same second — basenames differ by `<safe_branch>`
  suffix; no collision handling needed (same behavior as today).
- Verification: `grep -c 'date +%Y-%m-%d-%H%M%S' plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`
  prints `0`; `bash plugins/soleur/test/worktree-manager-cleanup-merged-no-worktree.test.sh`
  prints its pass line and exits 0.

## Open Code-Review Overlap

1 open code-review issue touches `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`:

- **#8496** "review: cleanup-merged never gh-queries [gone] branches that have no worktree" —
  **Acknowledge.** Different concern (the gh merged-PR query scope), explicitly scoped out of
  PR #8493 as contested-design with re-eval by 2026-10-21. This plan's two lines do not touch
  the gh-query loop; folding in would violate #8496's own scope-out justification.

## Dependencies & Risks

- No dependencies, no new files, no interface changes.
- Risk: the fixture edits must follow the suite's `assert_fixture_dir`/per-arm-`$TMP`
  conventions; a fixture placed outside `$TMP` would trip the canonical helpers by design.
- Risk: a future third archive-name producer in the script would bypass the property — mitigated
  by the assertion quantifying over *produced basenames* (any new producer in the reap path that
  names an archive entry for the fixture slug lands in an asserted namespace only if it writes
  to `specs/archive` or `plans/archive`; a producer writing elsewhere is a new surface).

## References

- Issue: #9091 — machinery: worktree-manager archive stamp uses dashed YYYY-MM-DD-HHMMSS
- Surfaced during: PR #9087 review (convergent P3)
- Related scope-out: #8496 (acknowledged above)
- Reference producer: `plugins/soleur/skills/archive-kb/scripts/archive-kb.sh:171`
- Suite under extension: `plugins/soleur/test/worktree-manager-cleanup-merged-no-worktree.test.sh`
  (provenance: #8400, fixed by PR #8418 — verified live)
