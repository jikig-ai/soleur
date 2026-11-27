---
title: "feat: instrument one-shot/test-fix-loop to emit run_health.json + phase_prompts/ (Phase 1 prereq)"
type: feat
date: 2026-11-27
slug: feat-instrument-run-health-emit
branch: feat-one-shot-12573-run-health-emit
issue: 12573
closes: 12573
priority: p2-medium
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# feat: instrument one-shot/test-fix-loop to emit run_health.json + phase_prompts/ (Phase 1 prereq)

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed). No `spec.md` exists at `knowledge-base/project/specs/feat-one-shot-12573-run-health-emit/spec.md`. The parent spec `knowledge-base/project/specs/feat-12532-degraded-run-forensics/spec.md` carries `lane: cross-domain`, which matches the fail-closed default.

## Enhancement Summary

**Deepened on:** 2026-11-27
**Sections enhanced:** 4 attribution sentences (Overview, Local research, Split Assessment, Dependencies). No new research subsections.
**Research agents used:** none. `spawn_subagent` is not available in this process. Reviewed-Coverage: sequential-fallback. This pass is not an independent review.

### Key Improvements

1. Gates 4.5, 4.55, 4.6, 4.7, 4.8, 4.9, 4.10, 4.11, 4.12, and 4.13 were run in-process against the committed plan. 4.5 and 4.55 do not fire. 4.6, 4.7, 4.8, 4.11, and 4.12 pass. 4.9, 4.10, and 4.13 skip. No telemetry: none of those gates halted.
2. The only prose change is the stale "unpushed" label on `1fbfbca547`. That commit is the parent of docs commit `cf7d17e120` and is on `origin/feat-one-shot-12573-run-health-emit`. The branch at `cf7d17e120` is 26 behind `origin/main` and 20 ahead. This summary commit adds one docs commit and does not change the product diff.
3. `tasks.md` is unchanged. No design correction landed. The emitter, the seal rule, and the schema stay as they are on the branch.

### New Considerations Discovered

- Phase 4.4: no new SQL, lock, RPC, pool, or circuit-breaker. The helper's existing same-directory replace is a 2026-11-20 ruling. This pass does not reopen it and does not add a precedent diff.
- Phase 4.10 word hits are not a store this slice creates. The Scope Check sibling filter names `proposal-queue`. Dependencies names the existing `plugins/soleur/test/cloud-init-user-data-size.test.ts` from `48f2d6761c`. Files to Edit stay the three skill markdown files. No Encryption Posture section.
- Phase 4.45: the plan body has no `NEVER`, `MUST NOT`, `does not reach`, `cannot leak`, or `is not exposed` claim. Local read of `plugins/soleur/scripts/run-health-emit.sh` confirms discover writes the fixture into a temp prompt file, prints `ok` on stdout, and sends `run-health-emit:` diagnostics to stderr.
- The CMO skip sentence in Domain Review is the body of `256418635b`, an ancestor of HEAD. No CPO sign-off is claimed. `requires_cpo_signoff` stays true.
- Phase 4.13 does not fire: Files to Create is None, and the edits are three skill markdown files, not a new workflow, cron, or host scheduler.

## Overview

Issue #12573 is still open. Open pull request #12996 already wires `plugins/soleur/scripts/run-health-emit.sh` into one-shot and test-fix-loop on this branch. This plan does not redesign that helper. It records the remaining work that lets #12996 merge: the read-surface failure that reddened CI on 2026-11-21, already addressed in commit `1fbfbca547` (on this branch's remote as the parent of `cf7d17e120`), and the 26 commits on `origin/main` that this branch does not yet contain.

"Run-health ledger" in this plan means the `run_health.json` file the helper writes. `knowledge-base/project/glossary.md` has no entry for that term.

## Research Insights

### Premise Validation

Checked on 2026-11-27. #12573 is OPEN (`gh issue view 12573 --json state,title`). Its `closedByPullRequestsReferences` names #12996, which is OPEN, MERGEABLE, and `mergeStateStatus` BEHIND (`gh pr view 12996`). `origin/main` has `plugins/soleur/scripts/run-health-emit.sh` (blob from `aae21955e6`, message `WIP: feat-12532-degraded-run-forensics (#12565)`) but `git grep run-health-emit origin/main` finds no call in `plugins/soleur/skills/one-shot/SKILL.md` or `plugins/soleur/skills/test-fix-loop/SKILL.md`. This branch's HEAD does. The premise "build the helper from nothing" is stale. The premise "finish #12996" holds.

#12532 is OPEN. #12574 is CLOSED. #12575, #12576, #12577, and #12578 are OPEN and stay out of this slice. Collision pre-check (`collision-precheck.sh 12573`) reported #12996, which is this vehicle, and two foreign `test-all.sh` processes in `.worktrees/feat-one-shot-9294-deploy-trio-prb` (pids 2290979 and 2624973). This plan does not start that suite.

CI run `44849280635`: job `test-webplat (2/2)` (`136676794950`) failed two assertions in `apps/web-platform/test/plugin-root-anchoring.test.ts` (`W4a` at the `toEqual([])` after the notice filter, `W4b` at `readSurfacePointerViolations`). The received paths were `plugins/soleur/skills/one-shot/references/run-health-schema.md` and relative links from `plugins/soleur/skills/one-shot/SKILL.md` and `plugins/soleur/skills/test-fix-loop/SKILL.md`. Job `test` (`136687276326`) failed in its aggregate step with `WEBPLAT_RESULT: failure` and the line `test-webplat: FAILED`. It is not a separate assertion failure. `##[error]rule-body-lint` lines in that log come from a vitest that expects `mandatory-human-review` on stderr (`apps/web-platform/test/server/inngest/rule-body-gate-recursion-invariant.test.ts`). The vitest summary for the failing shard was 2 failed tests, both in the anchoring file.

ADR keyword search under `knowledge-base/engineering/architecture/decisions/` for `run_health`, `run-health`, and `phase_prompts` returned no hits. The read-surface rule this CI failure enforces is ADR-179, which this plan follows rather than re-decides. No rejected-alternative in that corpus proposes this helper.

### Property List

- P1: A one-shot or test-fix-loop run leaves `run_health.json` and `phase_prompts/` on disk under `.soleur/runs/`.
- P2: The executing skill writes that record. A later summary does not reconstruct it.
- P3: The record is sealed at run exit with a terminal status.
- P4: The files are gitignored.
- P5: The schema is versioned and a unit test covers emission.
- P6: The pull request's anchoring checks pass so the record can merge.

### Cut List

- A second helper or a redesigned seal rule → P1–P3. Already covered by `plugins/soleur/scripts/run-health-emit.sh` on this branch and the 2026-11-20 rulings in `knowledge-base/project/specs/archive/20261120-163109-feat-one-shot-12573-run-health-emit/decision-challenges.md`. Do not reopen them.
- Sibling issues #12575–#12578 and an Article 30 register edit → not properties of #12573. Ruled out on 2026-11-27.
- Treating the `test` aggregate job as its own defect → P6. It only echoes `test-webplat` failure.

### Local research

Repo paths that matter:

- `plugins/soleur/scripts/run-health-emit.sh` — writer. `--discover` prints `ok` (verified 2026-11-27, exit 0).
- `plugins/soleur/scripts/run-health-emit.test.sh` — unit test already on the branch.
- `plugins/soleur/skills/one-shot/references/run-health-schema.md` — schema. On HEAD it contains `**Plugin root in this file:**` and `The root is ONLY the prefix of the path you read this file from`, which are `READ_SURFACE_NOTICE_HEAD` and `READ_SURFACE_CLOSED_RULE` in `plugin-root-anchoring.test.ts`.
- `plugins/soleur/skills/one-shot/SKILL.md` line with the `run-health-emit:start` marker — token-form link. File is 51630 bytes. Prior ruling cap is 52000.
- `plugins/soleur/skills/test-fix-loop/SKILL.md` — token-form link to the same schema.
- `.gitignore` — `.soleur/` at the line that ignores that directory.
- `apps/web-platform/test/plugin-root-anchoring.test.ts` — `W4a` and `W4b`.

`bun x vitest run test/plugin-root-anchoring.test.ts -t "W4a:|W4b:"` from `apps/web-platform` on 2026-11-27: 2 passed, 45 skipped. That tree includes `1fbfbca547`, which is now on this branch's remote.

Learnings that apply: `knowledge-base/project/learnings/2026-11-20-run-health-emit-must-seal-with-a-real-call.md` (seal is a real call). `knowledge-base/project/learnings/2026-11-08-a-credentialed-helper-must-run-its-verified-copy-and-a-refactor-strands-the-batteries-that-guard-it.md` (read each suite's own exit code; a trailing command is not the verdict). `knowledge-base/project/learnings/best-practices/2026-10-20-copied-template-links-and-coverage-negative-controls.md` (token-form links for Read-surface docs). ADR-179 is the anchoring contract. No external research: the codebase already contains the helper, the failing assertions, and the fix commit.

### Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| TR2 in `feat-12532-degraded-run-forensics/spec.md`: emission must be added to one-shot and test-fix-loop | Wired on this branch; absent from those two skills on `origin/main` | Keep the wiring. Do not write a second helper. |
| Brainstorm text from 2026-11-10 said neither skill emits the artifacts | Stale for this branch. True for `origin/main`. | Treat #12996 as the implementation. |
| Issue acceptance says artifacts are gitignored | `.gitignore` contains `.soleur/` | Keep that ignore. Do not commit a run directory. |

## Problem Statement / Motivation

Without a sealed on-disk record, a later forensic read has only the executing session's self-report. The record is implemented here and cannot merge while `test-webplat` fails. The failure is the schema doc becoming a Read-surface file (it contains the plugin-root token) without the notice and without token-form links from the two skills.

## Proposed Solution

Keep commit `1fbfbca547` (`fix(plugin): deliver the run-health schema through the plugin root`). It adds the root-delivery notice to the schema file and changes the two skill links from relative paths to `${CLAUDE_PLUGIN_ROOT}/skills/one-shot/references/run-health-schema.md`. Merge `origin/main` into this branch, re-run the two anchoring tests and `plugins/soleur/scripts/run-health-emit.test.sh`, and push. Do not change seal, fail-open exit 0, or `schema_version` unless a merge conflict forces a mechanical replay of the existing lines.

## Technical Considerations

- Architecture: no new ADR. The helper's decisions are the 2026-11-20 rows in the archived decision file. ADR-179 already requires the notice and the token-form link.
- Performance: one local JSON write per phase plus one seal. Not on a request path.
- Security: phase snapshots can hold session text. Storage stays under gitignored `.soleur/`. The helper stays fail-open and must not be taught to print prompt bodies on stdout.
- NFR: no change to a hosted service. `knowledge-base/engineering/architecture/nfr-register.md` is not re-scored; this slice adds no latency budget, availability target, or tenant boundary.
- Skill body: the `one-shot` ceiling in `plugins/soleur/test/skill-body-budget.json` is 52000, read on 2026-11-27. `wc -c plugins/soleur/skills/one-shot/SKILL.md` on HEAD is 51630 (370 bytes spare). `origin/main`'s copy is 51999 (1 byte spare). A clean `git merge-file` of this branch's file with `origin/main` at merge-base `c2da2ba0e459` is 51634 bytes (366 spare, zero conflict markers). Keep at least 50 bytes spare after the real merge (`wc -c` at most 51950). `test-fix-loop` is not a key in that ceiling file. `python3 scripts/lint-skill-body-budget.py --base origin/main` printed OK on this tree the same day.
- No `description:` edit on any `SKILL.md`, so the skill-description word budget is unchanged.

### Implementation Phases

#### Phase 1: Keep the helper

Do not edit `plugins/soleur/scripts/run-health-emit.sh` except to replay a conflict hunk that `origin/main` changed in the same lines. The replay keeps `--seal` plus a terminal status, exit 0 on a bad argument, and `schema_version` integer `1`.

#### Phase 2: Keep the read-surface commit

`1fbfbca547` is the fix for the two CI assertions. If a merge rewrites the schema notice, the notice must still contain both literals `**Plugin root in this file:**` and `The root is ONLY the prefix of the path you read this file from`. Both skill links stay token-form.

#### Phase 3: Integrate origin/main and re-measure

Merge `origin/main`. Then, from `apps/web-platform`, run `bun x vitest run test/plugin-root-anchoring.test.ts -t "W4a:|W4b:"`. From the repo root, run `bash plugins/soleur/scripts/run-health-emit.test.sh`. Both must exit 0. Re-measure `wc -c plugins/soleur/skills/one-shot/SKILL.md`. The number must be at most 51950 (at least 50 bytes under the 52000 ceiling). If the spare is thinner, trim prose in that file that is not an emission condition. Do not drop the run-health call or the token-form link to make the byte count.

#### Phase 4: Publish the branch on the existing pull request

Push `feat-one-shot-12573-run-health-emit` so #12996's next CI run includes `1fbfbca547` and the merge. Do not open a second pull request. Do not stage or delete `scripts/.h1probe.6G3BHeem.sh`.

## Files to Create

None.

## Files to Edit

- `plugins/soleur/skills/one-shot/references/run-health-schema.md` — keep the read-surface notice (`1fbfbca547`).
- `plugins/soleur/skills/one-shot/SKILL.md` — keep the token-form schema link inside the `run-health-emit:start` marker.
- `plugins/soleur/skills/test-fix-loop/SKILL.md` — keep the token-form schema link in the Run Health Emission section.

## User-Brand Impact

- **If this lands broken, the user experiences:** a pipeline run whose later forensic read finds no sealed `run_health.json`, so the only account of the failure is the session that produced it.
- **If this leaks, the user's workflow is exposed via:** prompt text under `.soleur/runs/<run-id>/phase_prompts/` entering git history if the ignore is dropped, or remaining readable on the machine that ran the pipeline.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one committed prompt snapshot exposes one person's session text. The bytes are local, not a hosted multi-tenant store, so the tier is not `aggregate pattern`. The gitignore does not lower the tier. `requires_cpo_signoff` stays true. `soleur:engineering:review:user-impact-reviewer` runs at review time. Live CPO spawn was not available in this process (see Domain Review).

## Observability

```yaml
liveness_signal:
  what: "plugins/soleur/scripts/run-health-emit.sh --discover prints ok after writing and sealing a temp ledger"
  cadence: "per discover invocation; a pipeline run writes once per phase plus one seal"
  alert_target: "stderr line prefixed run-health-emit:; the helper still exits 0"
  configured_in: "plugins/soleur/scripts/run-health-emit.sh --discover"
error_reporting:
  destination: "stderr prefix run-health-emit:; no Sentry project — the writer is a local gitignored file"
  fail_loud: "stderr line starting run-health-emit:"
failure_modes:
  - mode: "helper cannot create the run directory or the JSON write fails"
    detection: "stderr line run-health-emit: and no sealed file"
    alert_route: "the skill transcript keeps the stderr line; the pipeline continues"
  - mode: "ledger never sealed"
    detection: "run_health.json has sealed false after the exit call"
    alert_route: "run-health-emit.test.sh fails when --seal does not set sealed"
logs:
  where: "stderr of the helper, plus run_health.json and phase_prompts/ under .soleur/runs/<run-id>/"
  retention: "until the worktree or the local .soleur directory is removed; this slice adds no purge job"
discoverability_test:
  command: bash plugins/soleur/scripts/run-health-emit.sh --discover
  expected_output: "ok"
```

## Guard Contract

### Guard 1 — Read-surface schema docs are delivered through the plugin root

**Property.** A skill reference doc that carries the plugin-root token includes the root-delivery notice and the closed-rule sentence, and every other payload doc that names that file uses a token-form link.

**Assembly.** The chokepoint is `isReadSurfaceDoc` together with `readSurfacePointerViolations` in `apps/web-platform/test/plugin-root-anchoring.test.ts`. The population is whatever files that walk classifies, not a frozen list of today's two skills. A new reference doc that contains the token joins the population and must pass the same two assertions.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the notice head from `run-health-schema.md` while the token remains | RED (`W4a`) |
| 2 | Restore a relative link to that schema from one skill while the schema stays a Read-surface doc | RED (`W4b`) — this is the 2026-11-21 failure |
| 3 | After one skill is token-form, add a second payload doc that links to the same schema with a relative path | RED (`W4b` on the second member) |
| 4 | Make `isReadSurfaceDoc` return false for every file so the population is empty and the assertions compare `[]` to `[]` | RED (`W4d` floor on the population count) |
| 5 | Change the test's expected value for a compliant tree from `[]` to a hard-coded offender | RED (harness edit, not a product edit) |

Must-PASS, not the canonical tree: a reference doc that does not contain the plugin-root token is not a Read-surface doc, and a relative link to it stays green. `W4-control` in the same test file already encodes that discriminator.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Instrument `one-shot` and `test-fix-loop` to emit structured run-health artifacts at run exit:" [issue #12573] | Phase 1; existing helper and the two skill files | mapped |
| 2 | "`run_health.json` schema defined and versioned" [issue #12573] | `plugins/soleur/skills/one-shot/references/run-health-schema.md` | mapped |
| 3 | "`phase_prompts/` snapshotted before any retry overwrites them" [issue #12573] | Phase 1 helper, directory `phase_prompts` | mapped |
| 4 | "Ledger sealed at run exit before forensics spawns" [issue #12573] | Phase 1 `--seal` on the return path already in the schema's one-shot calls | mapped |
| 5 | "Artifacts are gitignored (not committed)" [issue #12573] | `.gitignore` `.soleur/` (already present; not a new edit) | mapped |
| 6 | "Unit tests for schema + emission" [issue #12573] | `plugins/soleur/scripts/run-health-emit.test.sh` (already on the branch) | mapped |
| 7 | "Finish open pull request #12996 in this existing worktree as the one-shot continuation of #12573 only." [brief] | Phase 4 | mapped |
| 8 | "Do not redesign the emitter." [brief] | Phase 1 | mapped |
| 9 | "Leave #12575, #12576, #12577, and #12578 until that pull request merges." [brief] | Out of scope in Dependencies | descoped — justification: the 2026-11-27 ruling keeps those issues out of this pull request |
| 10 | "Article 30 stays with soleur:legal:clo and is not this slice." [brief] | No legal-register edit | descoped — justification: the same ruling assigns Article 30 to the legal reviewer outside this slice |
| 11 | "Do not commit or delete scripts/.h1probe.6G3BHeem.sh." [brief] | Phase 4 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Phase 1 keep the helper | "Do not redesign the emitter." | asked |
| Phase 2 schema notice and token links | — | inferred — justification: CI job 136676794950 failed `W4a` and `W4b` on the schema file this issue adds; ADR-179's read-surface walk fails the pull request until the notice and token-form links land |
| Phase 3 merge `origin/main` | — | inferred — justification: `gh pr view 12996` on 2026-11-27 reported `mergeStateStatus` BEHIND (26 commits); the anchoring literals can move on main, so the local green run must be repeated after the merge |
| Phase 4 push #12996 | "Finish open pull request #12996 in this existing worktree as the one-shot continuation of #12573 only." | asked |
| `plugins/soleur/skills/one-shot/SKILL.md` | "Instrument `one-shot` and `test-fix-loop` to emit structured run-health artifacts at run exit:" | asked |
| `plugins/soleur/skills/test-fix-loop/SKILL.md` | "Instrument `one-shot` and `test-fix-loop` to emit structured run-health artifacts at run exit:" | asked |
| `plugins/soleur/skills/one-shot/references/run-health-schema.md` | "`run_health.json` schema defined and versioned" | asked |
| Leave `scripts/.h1probe.6G3BHeem.sh` unstaged | "Do not commit or delete scripts/.h1probe.6G3BHeem.sh." | asked |

### Split Assessment

- Subsystems touched: 1 — `plugins/soleur`
- Planned files: 3 | Estimated changed lines: 40 (the read-surface commit is +4/−2; the rest is merge-conflict slack)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

The branch diff against `origin/main` is already about 1123 lines inside #12996. Splitting that pull request would abandon the vehicle the 2026-11-27 ruling names. The remaining plan delta is under the thresholds.

## Acceptance Criteria

- [ ] `plugins/soleur/skills/one-shot/references/run-health-schema.md` states that schema_version is the integer 1. Verification: `grep -nF 'is the integer' plugins/soleur/skills/one-shot/references/run-health-schema.md` prints that line. Ran on 2026-11-27 and printed the schema line.
- [ ] `plugins/soleur/scripts/run-health-emit.sh` creates `phase_prompts` under the run directory before copying a prompt. Verification: `grep -nF 'mkdir -p "$RUN_DIR/phase_prompts"' plugins/soleur/scripts/run-health-emit.sh` prints that mkdir line. Ran on 2026-11-27 and printed it.
- [ ] The schema file's seal rule says a terminal status passed with `--seal` sets `sealed`. Verification: `grep -nF 'and a terminal' plugins/soleur/skills/one-shot/references/run-health-schema.md` prints the seal rule line.
- [ ] `.gitignore` contains a line `.soleur/`. Verification: `grep -n '^\.soleur/$' .gitignore` prints that line.
- [ ] `bash plugins/soleur/scripts/run-health-emit.test.sh` exits 0.
- [ ] From `apps/web-platform`, `bun x vitest run test/plugin-root-anchoring.test.ts -t "W4a:|W4b:"` reports 2 passed.
- [ ] `wc -c plugins/soleur/skills/one-shot/SKILL.md` prints a number at most 51950. That is 50 bytes under the `one-shot` ceiling 52000. HEAD measured 51630 on 2026-11-27. The clean merge-file result against `origin/main` measured 51634 the same day.
- [ ] `git diff --name-only origin/main...HEAD | grep -Ei 'triage-agent|redaction-gate|proposal-queue|session-end-trigger'` prints nothing. Ran on 2026-11-27 and printed nothing. That is the file-name check that #12575, #12576, #12577, and #12578 stay out of this branch.
- [ ] `git status --short` does not show `scripts/.h1probe.6G3BHeem.sh` as staged. The untracked file may remain.

## Domain Review

**Domains relevant:** Engineering, Product

Assessment questions: Engineering matches because the slice keeps a skill-level emission contract and must not diverge from ADR-179. Product matches only through fail-closed lane expansion and the single-user threshold (no new page or flow). Marketing, Operations, Legal, Sales, Finance, and Support do not match their assessment questions. Legal document work, including Article 30, is descoped. CMO already recorded a skip on this branch (`256418635b`, local ledger is not a founder outcome). No UI-surface path is in Files to Create or Files to Edit (`ui-surface-terms.md` excludes SKILL.md orchestration edits).

### Engineering

**Status:** error
**Assessment:** `spawn_subagent` is not a tool in this worker process (`search_tool` returned no spawn tool). Partial read by the planner: #12573 is OPEN; the helper on this branch already implements the 2026-11-20 seal and fail-open rulings; the CI defect is the read-surface notice, fixed in `1fbfbca547` and re-measured green locally. No new architecture.

### Product/UX Gate

**Tier:** none
**Decision:** reviewed (partial)
**Agents invoked:** none
**Skipped specialists:** soleur:product:cpo (spawn tool absent; threshold sign-off remains required and is not claimed as given), soleur:product:spec-flow-analyzer (same), soleur:marketing:copywriter (no user-facing copy)
**Pencil available:** N/A (no UI surface)

#### Findings

No page, component, or flow. The user-facing artifact is a missing forensic file when emission breaks, which is the User-Brand Impact section, not a wireframe. CPO sign-off is still required before review closes the threshold; this plan does not record it as done.

## Test Scenarios

- unit: Given the schema file on HEAD, when `W4a` runs, then the notice filter's offender list is empty.
- unit: Given the two skill links on HEAD, when `W4b` runs, then `readSurfacePointerViolations` returns an empty list.
- unit: Given a temp run dir, when `bash plugins/soleur/scripts/run-health-emit.sh --discover` runs, then stdout is `ok` and the exit code is 0.
- unit: Given `bash plugins/soleur/scripts/run-health-emit.test.sh`, when it finishes, then the exit code is 0 (seal, missing-file goto count, and fail-open arms already live in that file).
- integration: Given `origin/main` merged into this branch, when the two commands in Phase 3 run again, then both still exit 0. This re-measure is part of the change, not an ambient machine property.

## Success Metrics

- #12996's `test-webplat` shard that runs `plugin-root-anchoring.test.ts` no longer reports `W4a` or `W4b` failures.
- The aggregate `test` job is red only when a leg other than that already-fixed shard is red.
- One-shot `SKILL.md` stays at or under 51950 bytes (at least 50 bytes under the 52000 ceiling).

## Dependencies & Risks

- At `cf7d17e120` on 2026-11-27, #12996 is 26 commits behind `origin/main` and 20 ahead (`git rev-list --left-right --count origin/main...HEAD` printed `26` then `20`). The same-day count before the plan docs commit was 19 ahead. The Enhancement Summary commit adds one docs commit on top of that 20 and does not change the product diff. A merge can move `READ_SURFACE_NOTICE_HEAD`. Phase 3 re-measures the anchoring tests and the one-shot byte spare. `plugins/soleur/test/cloud-init-user-data-size.test.ts` and `scripts/test-affected-kb-consumers.baseline.txt` are already on this branch (`48f2d6761c`, the spec-mention floor). They are not a remaining edit and they are not #12575–#12578.
- Foreign `test-all.sh` processes are running in another worktree. Do not start `scripts/test-all.sh` from this plan.
- Untracked `scripts/.h1probe.6G3BHeem.sh` must stay unstaged. A directory `git add` would sweep it in.
- Out of scope: #12575, #12576, #12577, #12578, Article 30, and any edit whose purpose is a new emission design.
- Open code-review issues: none of the 96 open `code-review` issues contain the three skill paths or the helper path in the body (queried 2026-11-27).

## Open Code-Review Overlap

None.

## References & Research

- Issue #12573, pull request #12996, parent #12532.
- Archived implementation plan (do not copy; the emitter decisions live there): `knowledge-base/project/plans/archive/20261120-163109-2026-11-20-feat-emit-run-health-artifacts-plan.md`.
- Archived rulings: `knowledge-base/project/specs/archive/20261120-163109-feat-one-shot-12573-run-health-emit/decision-challenges.md`.
- CI: actions run `44849280635`, jobs `136676794950` and `136687276326`.
- ADR-179, enforced by `apps/web-platform/test/plugin-root-anchoring.test.ts`.

## Plan Review

The reviewer panel was not spawned. This process has no spawn tool (`search_tool` for `spawn_subagent` returned none). Standing checks applied on 2026-11-27, without a claim that an independent panel ran:

- Each acceptance criterion is a local post-condition. None waits on a GitHub run conclusion.
- There is no post-merge operator section.
- Cited `knowledge-base/**/*.md` paths in this plan exist on disk.
- Issue titles for #12573, #12532, #12575, #12576, #12577, and #12578, and pull request #12996, were re-read with `gh` on 2026-11-27.
- `bash plugins/soleur/scripts/run-health-emit.sh --discover` printed `ok` and exited 0. The command has no shell-active token.
- `bash plugins/soleur/scripts/run-health-emit.test.sh` exited 0 (27 passes). From `apps/web-platform`, the W4a/W4b vitest filter reported 2 passed.
- No taste item is left for the operator. The vehicle ruling is already recorded for `knowledge-base/project/specs/feat-one-shot-12573-run-health-emit/decision-challenges.md`.

## Sharp Edges

- An acceptance criterion that says "GitHub CI is green" can flip because a runner or a workflow on main changed. The criteria above call the local vitest filter and the helper unit test instead.
- `origin/main`'s one-shot skill measured 51999 bytes on 2026-11-27, one byte under the ceiling. The clean merge-file result is 51634 because this branch's body is smaller and main's delta since `c2da2ba0e459` is 4 bytes. Phase 3 still re-measures and keeps at least 50 bytes of spare. A pass at exactly 52000 is not the bar.
- The `test` job name looks like a unit-test failure. Its log's `WEBPLAT_RESULT: failure` is the aggregate of the anchoring shard. Fixing the aggregate script would not clear the red.
- A whole-repo `git add` picks up `scripts/.h1probe.6G3BHeem.sh`. Stage paths one by one.
- Quoting the relative link `./references/run-health-schema.md` inside `plugins/soleur/skills/one-shot/SKILL.md` as an instruction reintroduces `W4b`. The live link stays token-form. This plan file is not a payload doc in that walk.
