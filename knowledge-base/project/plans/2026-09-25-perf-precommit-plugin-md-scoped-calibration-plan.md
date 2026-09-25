---
title: "perf(hooks): scope the skill-security-scan corpus calibration to staged SKILL.md files in the plugin-markdown pre-commit hook"
date: 2026-09-25
slug: perf-precommit-plugin-md-scoped-calibration
branch: feat-one-shot-precommit-plugin-md-affected
pr: 8878
type: perf
lane: cross-domain
brand_survival_threshold: none
---

# perf(hooks): stop paying a whole-corpus security recalibration on every plugin-markdown commit

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed). (No `spec.md` exists for this branch.)

## Overview

`lefthook.yml` › `pre-commit` › `plugin-component-test` runs `bun test plugins/soleur/test/` (89 bun
files, ~3,700 tests) whenever any staged file matches `plugins/soleur/**/*.md`. The operator measured
204 s for a one-bullet markdown edit on a contended machine (2026-09-25).

The brief proposed routing plugin markdown through the affected selector
(`bash scripts/test-all.sh --affected`) and asked for that to be verified by measurement first.
**The measurement refutes that route** (details in Research Insights):

1. `test-all.sh --affected`'s selection unit is the *registration*, and the whole plugin bun corpus is
   ONE registration — `run_suite "plugins/soleur" bun test plugins/soleur/` (`scripts/test-all.sh`,
   "Named bun-test entries — bun shard" block). Its argv literal `plugins/soleur/` is a substring of
   every plugin path, so every plugin-markdown edit selects the whole plugin corpus (a *superset* of
   today's `plugins/soleur/test/`), plus 214 other registrations. Measured for
   `plugins/soleur/skills/plan/SKILL.md`: **215/517 suites selected, 241 s of classification alone**
   with suite execution stubbed out. Strictly worse than today.
2. The 204 s is not spread over ~80 suites. Per-file profiling of today's hook command shows
   **one test is 66% of the wall**: `skill-security-scan.test.ts` › "calibration corpus" ›
   `0% of first-party SKILL.md emit HIGH-RISK` = **116.5 s** of a 176 s run. It spawns
   `run-scan.sh` serially over all 103 first-party `SKILL.md` files. The other 88 files together
   total ~35 s of test time.

So the fix goes where the cost is. A skill's scan verdict is a pure function of **that skill's
`SKILL.md` content plus the scanner** (`runScanVerdict` pipes the one file into `run-scan.sh` on
stdin). A markdown commit can therefore change only the verdicts of the `SKILL.md` files it stages —
unless it stages the scanner itself. The hook passes its staged markdown list to the suite; the
calibration then scans only those `SKILL.md` files (full corpus if the scanner is staged); CI never
scopes. Everything else in the plugin suite keeps running on every plugin-markdown commit, so no
markdown validator loses local coverage.

Expected effect: ~176 s → ~50 s under the same load (−116 s, +~1.2 s per staged `SKILL.md`), for
every plugin-markdown commit, including agent and `references/` edits where the calibration
contributed nothing at all.

## Research Reconciliation — Brief vs. Codebase

| Brief claim | Reality (measured / read) | Plan response |
|---|---|---|
| Route plugin md through the affected selector (widen `bun-test` glob or re-point `plugin-component-test` at `test-all.sh --affected`) | `plugins/soleur` is one monolithic registration; argv-substring derivation selects it for **every** plugin path. SKILL.md arm: 215/517 selected incl. `plugins/soleur` = `bun test plugins/soleur/`; 241 s classification with execution stubbed | Rejected. Neither glob nor `run:` of `bun-test` changes. |
| "If it does not select, add missing declared edges in `scripts/lib/test-affected-paths.sh`" | Moot: the selector over-selects, it does not under-select. Declared edges are per-registration and are UNIONED with derived edges (rung 2–3 ∪ rung 4, `_affected_classify` doc) — no declaration can narrow `plugins/soleur` | No edit to `test-affected-paths.sh`, hence no conflict with the two sibling PRs editing it |
| ~80 bun suites, the blanket run is the cost | 89 files; `skill-security-scan.test.ts` = 127.9 s of 163 s summed test time; its corpus calibration alone = 116.5 s | Scope the calibration, keep the other 88 files |
| work/ship SKILL.md prose mentions `plugin-component-test` ~65 s | Only `plugins/soleur/skills/ship/SKILL.md` Phase 7 merge step 4 ("`plugin-component-test` runs `bun test plugins/soleur/test/` (~65 s)"); nothing in work/SKILL.md or AGENTS rules | Update that one sentence |
| Consider `bun-test` `skip: merge` and its interaction with md | `lefthook-bun-test-merge-skip.test.sh` pins `bun-test` as the **only** pre-commit command with a `skip` (#7941 Thread 3). With scoping, a merge commit's calibration cost is bounded by the count of `SKILL.md` files the merge stages | No `skip: merge` on `plugin-component-test`; pin test unchanged |

## Research Insights

### Premise validation

- No `#N` issue cited by the brief; draft PR #8878 is this branch. The #8634 audit file is not touched.
- `plugin-component-test` exists as described (`lefthook.yml`, priority 7, glob `plugins/soleur/**/*.md`,
  `run: unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_TEMPLATE_DIR GIT_EXEC_PATH && bun test plugins/soleur/test/`).
- `bun-test` exists as described (glob `*.{ts,tsx,js,jsx}`, `skip: [merge]`, `run: bash scripts/test-all.sh --affected`).
- The brief's "likely shape" was conditional on a measurement; the measurement refuted it (table above).
  This is the brief's own escape hatch, not a reversal of operator direction.

### Property list (Phase 0.6b)

- **P1.** A plugin-markdown commit's pre-commit cost is dominated by what the staged edit can move, not by
  a whole-corpus recalibration the edit cannot affect.
- **P2.** Every plugin bun suite that validates markdown still runs locally on a plugin-markdown commit
  (no local coverage drop for the 88 non-calibration files).
- **P3.** A staged `SKILL.md` that scans HIGH-RISK still fails the commit locally.
- **P4.** CI keeps the full calibration (0% HIGH-RISK, <5% REVIEW over every first-party `SKILL.md`)
  regardless of any local scoping input.
- **P5.** The hook's test runner still starts with the git-location family unset (#7833).

### Cut list (Phase 0.6b)

- Widen `bun-test` glob / re-point at `test-all.sh --affected` → P1 → makes P1 worse (measured above).
- Declared edges in `scripts/lib/test-affected-paths.sh` → P1 → cannot narrow a monolithic registration.
- A new per-file bun selector + a classification census over 89 files → P1 → buys at most the ~35 s
  residual, most of which is corpus validators every md edit legitimately affects (components,
  harness-parity, invocation-axis, workflow-fidelity …). Disproportionate; rejected (see Alternatives).
- `skip: merge` on `plugin-component-test` → no property requires it; conflicts with the pinned
  "bun-test is the only skipper" invariant.

### Measurements (Phase 0.6c) — commands that produced the numbers

Load average during measurement: 10–30 on 16 cores (contended, like the operator's 204 s run).

1. **Affected-selector arm (SKILL.md).** Sandboxed copy of `scripts/test-all.sh` + its three libs in
   the scratchpad, with the same two splices `scripts/test-all-affected.test.sh` `build_sandbox()` uses
   (the `SANDBOX_DIFF_NAMES` seam before `_diff_touches() {`, and `"$@" || rc=$?` replaced by a RAN
   record), run from the worktree root:
   `env -u CI … SOLEUR_DISABLE_SESSION_STATE=1 SANDBOX_RECORD=<rec> SANDBOX_DIFF_NAMES='plugins/soleur/skills/plan/SKILL.md' bash <sb>/test-all.sh --affected`
   → `=== 215/517 suites passed ===`, rc 0, **241 s wall**, RAN records include
   `plugins/soleur<TAB>bun test plugins/soleur/` and `apps/web-platform [repo-wide+component]`.
   Agent `.md` and `references/*.md` arms were not separately timed: the same `plugins/soleur/`
   argv-substring edge matches every path under `plugins/soleur/` by construction
   (`_diff_touches`: `[[ "$_diff_names" == *"$p"* ]]`).
2. **Per-file cost of today's hook command.**
   `bun test plugins/soleur/test/ --reporter=junit --reporter-outfile=<x>` then summing
   `<testcase time>` per file → `Ran 3700 tests across 89 files. [176.13s]`;
   `skill-security-scan.test.ts` 127.86 s (22 tests); next-largest files 3.33 s
   (`validate-seo`), 3.30 s (`terraform-target-parity`), 3.00 s (`model-launch-review`);
   all 88 non-scanner files sum to 35.3 s.
3. **Within the scanner suite:** `0% of first-party SKILL.md emit HIGH-RISK` = **116.53 s** (it
   populates the shared `runCorpus()` cache; the `<5% REVIEW` test then reuses it);
   `run-self-test.sh exits 0 on the bundled fixtures` = 4.60 s; the rest < 1 s each.
4. **Corpus-validator subset** (components, harness-parity(-tree), invocation-axis, workflow-fidelity,
   devin-cloud-mode, grok-harness-invoke, grok-inspect-contract, fable-consult-gates,
   scratch-path-collision, observability-schema-parity, skill-security-scan): 56 s wall, of which
   the scanner suite is 52 s — every other corpus validator is sub-second to ~2 s.

### Relevant files

- `lefthook.yml` — `pre-commit` › `plugin-component-test` (the #7833 comment block above `run:` is
  load-bearing *and* is cited by `scripts/markdown-lint.test.sh` T6 prose — keep it).
- `plugins/soleur/test/skill-security-scan.test.ts` — `runScanVerdict()` (stdin-only scan of one
  file), `describe("skill-security-scan: calibration corpus (Phase 7 AC)")`, `discoverFirstPartySkills()`,
  `runCorpus()` cache; both calibration tests carry a 180 000 ms timeout.
- `.github/workflows/skill-security-scan-corpus.yml` — CI calibration on push to main and on PRs
  touching the rule pack, the scanner scripts, or `plugins/soleur/test/skill-security-scan.test.ts`
  (so THIS PR triggers it). GitHub Actions sets `CI=true` for every step.
- `scripts/test-all.sh` › `run_suite "plugins/soleur" bun test plugins/soleur/` — CI's `test-bun`
  shard runs the scanner suite unscoped on every PR.
- `plugins/soleur/test/hook-git-env-coverage.test.sh` (Guard 2) — parses every lefthook `run:`,
  requires `unset <all 9 vars>` as a statement BEFORE any runner statement; floors run-lines ≥ 26
  (currently 32), runners ≥ 3 (currently 3). Unchanged count after this plan.
- `plugins/soleur/test/lefthook-bun-test-merge-skip.test.sh` — pins `bun-test` glob/run/skip and
  "bun-test is the only skipper". Untouched stanza → stays green.
- `plugins/soleur/test/fanout-suite-scope.test.sh` — pins `test-all.sh --affected` in lefthook.yml;
  unaffected (no test-all invocation added or removed).
- `plugins/soleur/skills/ship/SKILL.md` — Phase 7 merge step 4 prose (the "~65 s" sentence).
  Body budget: 271 033 B of the 274 000 B ceiling in `plugins/soleur/test/skill-body-budget.json`
  (enforced against the merge base by `scripts/lint-skill-body-budget.py`) → 2 967 B headroom; the
  edit must be net-neutral or shrink.
- `.claude/hooks/skill-security-scan.sh` via `skill-security-scan-advisory` (priority 7) already
  scans staged `SKILL.md`/agent `.md` per commit — advisory (always exit 0). It is NOT a substitute
  for P3, which needs a blocking check; the scoped calibration provides that.

### Institutional learnings

- `knowledge-base/project/learnings/2026-09-23-the-deferral-rested-on-a-sentence-nobody-had-measured.md`
  item 12 — a markdown-only commit's `plugin-component-test` "timed out two unrelated suites under
  load"; the recovery re-ran "LOW-RISK scan" in isolation. The scanner calibration timing out under
  contention is a recurring class this plan removes from the hook path.
- `knowledge-base/project/learnings/test-failures/2026-09-22-verify-by-manifest-not-by-executing-the-candidate.md`
  item 3 — hook reds must be diffed against `origin/main`; pre-existing reds are excluded by hook
  name, not by disabling the gate.
- `2026-03-21-lefthook-gobwas-glob-double-star.md` — glob semantics; the glob is unchanged here.
- `#7833` (archived spec `feat-one-shot-7833-git-dir-beats-cwd`) — why the `unset` prefix exists;
  it stays the first statement.

### Conventions honoured

`cq-write-failing-tests-before` (unit rows first), `cq-assert-anchor-not-bare-token` (the lefthook
pin compares the parsed `run:` string exactly, not a token grep), `cq-test-fixtures-synthesized-only`,
`hr-verify-repo-capability-claim-before-assert` (both "cannot narrow" claims above were read from
`_affected_classify`'s precedence doc and measured).

### Plan review (single seat, proportional per operator direction)

`soleur:engineering:review:code-simplicity-reviewer`, combined simplicity + correctness brief. Applied:

- **Correctness (mechanical):** the planned scanner-self escalation keyed on `.md` paths under
  `skills/skill-security-scan/`, but `{staged_files}` carries only `*.md` and no scanner `.md`
  changes a verdict (re-verified: the scanner scripts read no `.md`; `*.skill.md` fixtures feed the
  unscoped fixture matrix). Dropped.
- **Simplicity (taste, applied — headless, no operator direction contradicted):** the separate
  scope module, its unit-test file, the exact-equality lefthook pin, and quote/CR stripping are cut.
  Scoping is ~6 lines narrowing the existing `skills` binding, so every consumer reads one variable;
  the verification is behavioural (Phase 3 rows) plus the AC8 census. Guard 2 and the merge-skip pin
  already cover the unset order and the "no skip" invariant.
- Confirmed not-red: Guard 2 statement split of the new `run:`, merge-skip pin, `markdown-lint.test.sh`
  T6 prose, `web-platform-runtime-plugin-trigger.test.ts` comment, corpus workflow (variable unset).

## Implementation Phases

### Phase 1 — Scope the calibration (test file)

1.1 **Edit** `plugins/soleur/test/skill-security-scan.test.ts`, calibration `describe` only (≈6–10
lines; no new module):

```ts
// inside describe("skill-security-scan: calibration corpus (Phase 7 AC)")
const all = discoverFirstPartySkills();
// Set only by lefthook's plugin-component-test (newline-separated staged plugin .md paths).
// CI is never scoped: the required checks own the full corpus.
const scopeRaw = process.env.SOLEUR_SKILL_SCAN_CALIBRATION_SCOPE;
const scoped = scopeRaw !== undefined && !process.env.CI;
const staged = new Set((scopeRaw ?? "").split("\n").map((l) => l.trim()).filter(Boolean));
const skills = scoped ? all.filter((abs) => staged.has(relative(REPO_ROOT, abs))) : all;
console.log(`[skill-security-scan calibration] ${scoped ? "scoped" : "full"} ${skills.length}/${all.length}`);
```

- `runCorpus()` and both assertions keep reading `skills` — there is no second variable a later edit
  could iterate by mistake;
- `0% … HIGH-RISK`: `test.skipIf(scoped && skills.length === 0)` — a scoped run with no staged
  `SKILL.md` (agent or `references/` edit) SKIPS visibly instead of passing over an empty set;
- `<5% … REVIEW`: `test.skipIf(scoped)` — the ratio is a corpus property; CI owns it;
- test names unchanged (verified: nothing outside this file names them);
- import `relative` from `node:path`; update header comment item 3 (scope seam, CI ignores it).

Shape is illustrative; Phase 3's rows are the contract. No scanner-self escalation: `{staged_files}`
carries only `*.md`, and no scanner `.md` changes a verdict (the scripts read no `.md`; the
`references/test-fixtures/*.skill.md` fixtures feed the always-unscoped fixture-matrix tests, not the
calibration). Rule-pack/script changes (`.yaml`/`.sh`) never reached this hook's scope and are
covered by `skill-security-scan-corpus.yml`'s `paths:` trigger in CI.

### Phase 2 — Wire the hook and fix the one doc sentence

2.1 **Edit** `lefthook.yml` › `plugin-component-test`:

- `run:` becomes
  `unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_TEMPLATE_DIR GIT_EXEC_PATH && SOLEUR_SKILL_SCAN_CALIBRATION_SCOPE="$(printf '%s\n' {staged_files})" bun test plugins/soleur/test/`
  (the `unset` statement stays FIRST and complete — Guard 2 and P5; `{staged_files}` is already
  filtered to `plugins/soleur/**/*.md` by the command's glob; the assignment is unconditional, never
  built from a `${X+…}` expansion);
- keep the #7833 comment block verbatim; add 3–5 comment lines ABOVE it: why the scope is passed
  (calibration = 116 of 176 s measured 2026-09-25; a verdict is a function of one `SKILL.md`), and
  that CI ignores it;
- glob, priority, and every other command unchanged. No `skip` key.

2.2 **Edit** `plugins/soleur/skills/ship/SKILL.md` Phase 7 merge step 4: replace
"`plugin-component-test` runs `bun test plugins/soleur/test/` (~65 s) whenever a
`plugins/soleur/**/*.md` is staged" with a sentence of equal or smaller byte length saying it runs
the plugin bun suite with the security-scan calibration limited to the staged `SKILL.md` files.
Net byte delta ≤ 0.

### Phase 3 — Verify (targeted; CI is the battery)

Per operator direction, no local full battery and no `test-all.sh --affected` run (measured at 215
suites for a plugin md diff). Each row names the mutation it catches (Guard Contract).

3.1 `SOLEUR_SKILL_SCAN_CALIBRATION_SCOPE=plugins/soleur/skills/ship/SKILL.md bun test plugins/soleur/test/skill-security-scan.test.ts`
    → green, log line `scoped 1/<N>`, wall < 20 s.
3.2 `SOLEUR_SKILL_SCAN_CALIBRATION_SCOPE=$'plugins/soleur/skills/plan/SKILL.md\nplugins/soleur/skills/ship/SKILL.md' bun test plugins/soleur/test/skill-security-scan.test.ts -t 'HIGH-RISK'`
    → log line `scoped 2/<N>` (second-member row).
3.3 `SOLEUR_SKILL_SCAN_CALIBRATION_SCOPE=plugins/soleur/agents/engineering/cto.md bun test plugins/soleur/test/skill-security-scan.test.ts`
    → log `scoped 0/<N>`; the two calibration tests are reported as **skip**, not pass.
3.4 CI override without paying the full scan: `CI=1 SOLEUR_SKILL_SCAN_CALIBRATION_SCOPE=plugins/soleur/skills/ship/SKILL.md bun test plugins/soleur/test/skill-security-scan.test.ts -t 'no-such-test-name'`
    → the collection-time log line reads `full <N>/<N>` (the describe body runs at collection; no
    test executes). Record the exit code bun gives for a zero-match filter; the log line is the
    assertion.
3.5 `bash plugins/soleur/test/hook-git-env-coverage.test.sh` → receipt `run_lines=32 runners=3`.
3.6 `bash plugins/soleur/test/lefthook-bun-test-merge-skip.test.sh` → 5/5.
3.7 **Dogfood:** the commit that stages `plugins/soleur/skills/ship/SKILL.md` fires the new hook for
    real (linked worktree, hooks live). Capture the lefthook summary line
    (`✔️ plugin-component-test (N seconds)`) and the `scoped 1/<N>` log line into
    `knowledge-base/project/specs/feat-one-shot-precommit-plugin-md-affected/measurements.md`
    alongside the 176 s baseline and the load average at the time. Confirm `git log -1` moved HEAD
    (learning 2026-09-23 item 11).
3.8 Push; the required checks (`test` aggregate incl. `test-bun`, and `skill-security-scan-corpus`
    triggered by the test-file path) must pass by name on the exact head SHA — they run the calibration
    unscoped (`CI=true`, variable unset).

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-precommit-plugin-md-affected/measurements.md` (work phase)

## Files to Edit

- `lefthook.yml` (`plugin-component-test` `run:` + added comment lines only)
- `plugins/soleur/test/skill-security-scan.test.ts` (calibration `describe` + header comment only)
- `plugins/soleur/skills/ship/SKILL.md` (one sentence in Phase 7 merge step 4, net ≤ 0 bytes)

Not edited: `scripts/lib/test-affected-paths.sh`, `scripts/test-all.sh`, the `bun-test` stanza,
`lefthook-bun-test-merge-skip.test.sh`, the #8634 audit file.

## Guard Contract

### Guard 1 — scoped calibration never narrows CI and never under-covers a staged skill

**Property.** The calibration scans the full first-party `SKILL.md` corpus whenever `CI` is set or
`SOLEUR_SKILL_SCAN_CALIBRATION_SCOPE` is unset; otherwise it scans exactly the staged paths that are
first-party `SKILL.md` files, and a scoped run over zero of them is reported as skipped, never passed.

**Assembly.** One chokepoint: the `skills` binding at the top of the calibration `describe` in
`plugins/soleur/test/skill-security-scan.test.ts` — `runCorpus()`, the HIGH-RISK assertion and the
REVIEW denominator all read that one binding. One producer: the `plugin-component-test` `run:` line,
the only setter of the variable (AC8 censuses the repo, plans/specs excluded, so a second setter —
a workflow, a script — is caught).

**Mutation matrix** (each must be caught by the named row):

| # | Mutation | Caught by |
|---|---|---|
| M1 | drop `&& !process.env.CI` | 3.4 — log reads `scoped 1/<N>` instead of `full <N>/<N>` |
| M2 | ignore the scope (always `all`) | 3.1 — log `full`, wall ≫ 20 s |
| M3 | keep only the first staged path | 3.2 — log `scoped 1/<N>` instead of `2/<N>` (second member) |
| M4 | match by basename (`SKILL.md`) instead of repo-relative path | 3.1 — count `<N>/<N>` instead of `1/<N>` |
| M5 | drop `skipIf` on zero targets | 3.3 — calibration tests reported `pass` over an empty set |
| M6 | a workflow or script also sets the variable | AC8 census |
| M7 | reorder the assignment before `unset`, or drop the `unset` | Guard 2 (`hook-git-env-coverage.test.sh`) for the unset; reviewer reads the one-line `run:` diff for order |

**Harness rows.** H1 (must go RED on the instrument): running 3.1 with the variable deliberately
unset must print `full` — proves the log line reflects the env, not a constant. H2 (must-PASS
non-canonical input): an agent `.md` path (3.3) and a `references/*.md` path both yield `scoped 0/<N>`
plus skip, not an error.

**Anchor.** CI's `CI=true` is set by GitHub Actions, outside any diff, and
`.github/workflows/skill-security-scan-corpus.yml` runs the calibration without the hook. One diff
cannot both weaken the scoping and make CI stop setting `CI`.

## User-Brand Impact

**If this lands broken, the user experiences:** (the user here is the plugin maintainer/operator) a
plugin-markdown commit either still waits ~3 minutes (no gain) or — the failure that matters — a
`SKILL.md` whose content newly trips a HIGH-RISK scan rule commits locally without a red, and is
caught only by CI's unscoped calibration on push.

**If this leaks, the user's workflow is exposed via:** no data, credential or network surface is
touched; the change is a local pre-commit test-selection input. The only exposure vector would be a
HIGH-RISK skill reaching `main`, which the required CI checks (`test-bun`, corpus calibration) block.

**Brand-survival threshold:** none

- threshold: none, reason: dev-loop hook + test-scoping change on no sensitive path; CI's required
  checks keep the full calibration and are the merge gate (ADR-183).

## Acceptance Criteria

- [ ] **AC1** `lefthook.yml` `plugin-component-test.run` equals the Phase 2.1 string (checked in
      review by reading the parsed value: `bun -e 'const y=Bun.YAML.parse(await Bun.file("lefthook.yml").text()); console.log(y["pre-commit"].commands["plugin-component-test"].run)'`);
      `glob` unchanged; no `skip` key.
- [ ] **AC2** `bash plugins/soleur/test/hook-git-env-coverage.test.sh` exits 0 and prints
      `SOLEUR_GUARD2_RECEIPT run_lines=32 runners=3` (unset still first; no entry point lost).
- [ ] **AC3** `bash plugins/soleur/test/lefthook-bun-test-merge-skip.test.sh` passes 5/5 unchanged.
- [ ] **AC4** Phase 3.1 — scoped run with one `SKILL.md`: green, log `scoped 1/<N>`, wall < 20 s
      (was 127.9 s for the file).
- [ ] **AC5** Phase 3.2 — two staged `SKILL.md` paths: log `scoped 2/<N>`.
- [ ] **AC6** Phase 3.3 — agent `.md` only: log `scoped 0/<N>`; both calibration tests reported as
      `skip` (bun's skip count rises by 2), not `pass`.
- [ ] **AC7** Phase 3.4 — `CI=1` plus a scope: collection log reads `full <N>/<N>`.
- [ ] **AC8** `git grep -n SOLEUR_SKILL_SCAN_CALIBRATION_SCOPE -- ':!knowledge-base/project/plans' ':!knowledge-base/project/specs'`
      lists only `lefthook.yml` and `plugins/soleur/test/skill-security-scan.test.ts`.
- [ ] **AC9** Dogfood commit staging `ship/SKILL.md`: `plugin-component-test` completes; seconds,
      load average and the `scoped 1/<N>` line recorded in `measurements.md` next to the 176 s baseline.
- [ ] **AC10** `ship/SKILL.md` byte size does not increase (`wc -c` before/after in `measurements.md`).
- [ ] **AC11** Required checks pass by name on the exact head SHA, including `skill-security-scan-corpus`
      (triggered by the test-file path) running the unscoped corpus.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — local developer-tooling change (pre-commit hook input and a
test's corpus scope). No user-facing surface, no infrastructure, no regulated data.

## Gates Not Applicable

- Observability (2.9): no Files-to-Edit under `apps/*/server|src|infra` or `plugins/*/scripts`; no new
  runtime surface. The failure surface is the committing terminal; CI is the enforcement.
- IaC (2.8), Encryption (2.11), GDPR (2.7), ADR/C4 (2.10): no infra, store, connection, regulated data,
  or architectural decision.
- Skill description budget (1.8): no `description:` edit.

## Test Scenarios

1. md-only commit touching an agent file → calibration skipped (scoped, 0 targets); all 88 other
   files run; commit time ≈ residual suite time.
2. md commit touching one `SKILL.md` → calibration scans that one skill; HIGH-RISK content fails the
   commit.
3. md commit touching the scanner's own `SKILL.md` → that one skill is calibrated like any other;
   scanner rule/script changes (`.yaml`/`.sh`) never reached this hook and stay with CI's
   `skill-security-scan-corpus` (previously a rules edit co-staged with any plugin `.md` got a full
   local calibration by accident; no longer).
4. conflict-resolved merge staging N skills → calibration scans N skills, each once.
5. CI (`CI=true`), any env → full calibration; `<5% REVIEW` asserted.
6. developer runs `bun test plugins/soleur/test/` by hand (no env) → full calibration, unchanged.

## Alternatives Considered

| Alternative | Verdict | Why |
|---|---|---|
| Re-point `plugin-component-test` at / widen `bun-test` to `test-all.sh --affected` | Rejected | Measured 215/517 suites, 241 s classification; selects the monolithic `plugins/soleur` registration |
| Split `run_suite "plugins/soleur"` into per-file registrations so `--affected` can narrow it | Rejected here | Touches shard totality, ordinal maps and CI shard manifests for the bun leg; the md-hook win is already captured by scoping. Would benefit plugin `.ts` commits via `bun-test`; not needed for this goal |
| New per-file bun selector for md (content reference + declared corpus list + census guard) | Rejected | Residual after scoping is ~35 s of mostly corpus validators every md edit affects; a census over 89 files is disproportionate |
| `bun test --changed` | Rejected | Import-graph based. Measured (bun 1.4.2, scratch repo: `a.test.ts` reads `doc.md` via `fs`, `b.test.ts` imports `mod.ts`): editing `doc.md` → `Ran 0 tests across 0 files`; editing `mod.ts` → 1 file. A md edit selects nothing |
| Parallelise `runCorpus()` spawns | Rejected | Keeps 103 scans per md commit; gains shrink under exactly the contention that motivated the ask; scoping is O(staged) |
| Exclude `skill-security-scan.test.ts` from the hook, rely on the advisory hook | Rejected | Advisory hook always exits 0 → loses P3 (blocking HIGH-RISK locally) |
| `skip: merge` on `plugin-component-test` | Rejected | Conflicts with the pinned sole-skipper invariant; scoping already bounds merge cost |

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` bodies checked for `lefthook.yml`,
`plugins/soleur/test/skill-security-scan.test.ts`, `plugins/soleur/skills/ship/SKILL.md`,
`plugin-component-test` — zero matches.)

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text,
  or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or
  `soleur:work`.
- The `unset` statement must remain the FIRST statement of the `run:` line and name all nine
  variables; putting the scope assignment in its own `&&` statement before the unset would still pass
  Guard 2 (an assignment is not a runner) but reorders the load-bearing prefix — keep Phase 2.1's
  order exactly.
- lefthook may split a command into several invocations when a `{staged_files}` expansion exceeds the
  platform's command-length limit (unverified for this lefthook version; not reachable on Linux for
  realistic merges). If it happens, the bun suite runs once per chunk, each chunk scoped to its own
  paths — slower, never less covered.
- `{staged_files}` is shell-escaped by lefthook. Verified with the repo's lefthook (v2.1.14, the
  binary `.git/hooks/pre-commit` resolves) in a scratch repo with the same glob and
  `X="$(printf '%s\n' {staged_files})"`: output was the two matching paths, one per line, unquoted,
  including one containing a space; a non-matching `other.md` was excluded. So the scope needs no
  quote-stripping or `\r` handling.
- An empty scope string is a real, meaningful input (md commit with no `SKILL.md`); never collapse it
  to "unset" (M2) — that would recalibrate the whole corpus on every agent/reference edit.
- `ship/SKILL.md` has 2 967 B of body-budget headroom against the merge base; the sentence edit must
  not grow the file.
- The hook's env var is inherited by every suite in the single `bun test` process and by their
  children; only the calibration reads it. Harmless, but a second reader belongs in the Guard 1
  assembly.
- Bun's `test.skipIf` is evaluated when the `describe` body runs (collection); compute `skills` there,
  never lazily inside a test body, or the zero-target case becomes a vacuous pass.
- An empty scope string cannot come from the hook (its glob guarantees ≥ 1 path); the meaningful
  case is a non-empty list with no `SKILL.md`, which is `scoped 0/<N>` + skip.
