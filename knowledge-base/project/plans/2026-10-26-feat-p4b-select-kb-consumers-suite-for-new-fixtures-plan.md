---
title: "feat: P4b select the kb-consumers suite when a new fixture names knowledge-base/"
date: 2026-10-26
slug: p4b-select-kb-consumers-suite-for-new-fixtures
branch: feat-one-shot-10924-p4b-kb-consumers-selection
issue: 10924
lane: cross-domain
type: feat
---

Spec lacks valid lane: defaulted to cross-domain (fail-closed). No `spec.md` exists for this one-shot branch.

## Overview

Item P4b of the follow-up list on #10924 (umbrella #9757, `Ref` only, neither is closed by this PR): the
local affected-tests gate should also run the dropped-consumer ratchet (`scripts/test-affected-kb-consumers`,
about 91 s) when a diff adds a test fixture or test file whose text names a knowledge-base path, so the red
that ratchet raises is seen before push instead of in CI.

**Re-scope after reading the code (disclosed, CTO-ruled).** The issue names `plugins/soleur/scripts/affected-tests.sh`
as the place that "selects" the suite. In this repo that script never selects anything itself: it is
plugin-generic and delegates to `bash scripts/test-all.sh --affected` (capability probe,
`affected-tests.sh` lines ~457-500), and it ships to other repositories, so it cannot name a repo suite. The
runner's selector matches diff PATHS only. Measured today:
`bash scripts/test-all.sh --print-selection --paths=plugins/soleur/test/fixtures/new-fixture.sh` prints
`AFFECTED_SELECTED scripts/test-affected-kb-consumers 0 edge:declared` (not selected; 247 of 671 suites
selected). Editing the runner to read added-line content is a `semantic` runner edit (full battery, derive
cache, replay mirror, three pinning suites). The ruled design (Option C, `decision-challenges.md`) keeps the file the brief names
and adds a generic, config-declared **content trigger** to the gate: when an added line (tracked files) or any
line (untracked files) of a changed file under configured path globs contains a configured fixed string, the
gate runs a configured command in addition to the delegated or adapter run. The repo's `.soleur-test-gate.json`
declares pattern `knowledge-base/` and command `bash scripts/test-affected-kb-consumers.test.sh`. No runner,
no `apps/**`, no workflow edit.

## Research Reconciliation — Spec vs. Codebase

| Spec / issue claim | Reality | Plan response |
|---|---|---|
| `affected-tests.sh` should "select the kb-consumers suite" | It delegates every `--affected` run to `scripts/test-all.sh`; selection is the runner's and is path-only (evidence above) | Add a generic content-trigger step to the gate (runs an extra declared command), configured from `.soleur-test-gate.json`; selection logic in the runner is untouched |
| "a new fixture contains `knowledge-base/`" | The only existing content-keyed trigger is the pre-push lane clause (b) (`scripts/pre-push-ratchet-lane.sh` lines ~355-378): added lines of `*.test.sh` / `test_*.sh` / `test-*.sh` only, not fixtures, `.ts`/`.py` tests, or untracked files | Cover those classes in the gate; the lane widening and the lane's dead `knowledge-base/` dir entry in `KB_CONSUMERS_INPUTS` (never matches under `grep -qxF`) are filed as #11166 |
| ADR-242 decision 19 reads as if the suite were always-on | #9763 withdrew it; selection is by declared edges (`scripts/lib/test-affected-paths.sh` lines 541-552) | No change; stated so the implementer does not "restore" it |
| "kb-consumers suite" is one place to select | The ratchet reports only registered suites' argv-named code (one hop) and dir-operand `*.test.*` files; an unregistered new file passes it | Documented blind spot; the trigger fires on the cheap necessary condition (a `knowledge-base/` literal in a new test-tree line), the ratchet decides |

## Research Insights

**Premise validation (Phase 0.6).** Cited: #10924 (open; P4a ticked, P4b-d open), #9757 (open), PR #11164 (draft, this branch),
`plugins/soleur/scripts/affected-tests.sh` and `scripts/test-all.sh` (both on `origin/main`). The ADR corpus was grepped for the mechanism
(content-keyed selection): ADR-242 decisions 19, 20, 22 and ADR-276 decision 5 discuss declared edges, the registration-only runner grammar
and `glob:` edges; none rejects a gate-side content trigger, and decision 22 explicitly leaves content selection to "its own mechanism".

**Property List (Phase 0.6b).**

1. A diff that adds a `knowledge-base/` literal to a test-tree file is detected before push without selecting by path alone.
2. The detection costs nothing on a diff that does not add that literal (no 91 s ratchet on every plugin test edit).
3. A detection failure never reads as "clean" (fail toward running the ratchet).
4. The plugin gate stays repo-agnostic and the exit contract (0/1/4/6/7) is unchanged.

**Cut List.** (a) Runner-side content scan in `scripts/test-all.sh` -> property 1 -> covered by a gate-side step that needs no runner edit (CTO ruling). (b) A `glob:` or path edge such as `plugins/soleur/test/*.test.sh` -> property 1 -> over-selects a 91 s suite on every plugin test edit, violates property 2. (c) Widening the pre-push lane in this PR -> property 1 -> a different gate, filed as #11166. (d) An array-of-objects config -> property 1 -> three flat keys cover the single trigger (the config reader decodes scalar arrays only).

**Value-proposition measurement (Phase 0.6c).** Saving claimed: avoid a CI-only ratchet red (a full merge-queue cycle, about 148 job-minutes per candidate run per ADR-276). Cost measured:
the ratchet is about 91 s (`scripts/suite-durations.tsv`); trigger rate measured with `git diff-tree -p -U0` over the last 150 first-parent non-merge commits of `origin/main`, counting commits that ADD a line containing the literal to a non-markdown/non-data file:
test and fixture trees excluding `apps/` 11/150 (7.3%); plus `scripts/**` 16/150 (10.7%); plus `apps/` tests 23/150 (15.3%). The measuring scripts are session scratch; Phase 0 re-runs the final glob set and records the number (threshold: at or under 10%, CTO flip evidence).

**Institutional learnings applied.** 2026-10-01 grep-q pipefail (grep a FILE, never `producer | grep -q`); the 73% whole-content trigger (added lines only, path-limited);
ratchet authoring constraint (a literal `knowledge-base/` on a line without a fixture word is read as a real read: string-join it in the new test rows, e.g. `"knowledge""-base/"`);
2026-10-14 ratchets no file query selects (explicit pre-push list below); 2026-10-22 gate queued 40+ min behind stale runs (use `list_runs` / `kill_mine` from `plugins/soleur/scripts/lib/proc.sh`, CI is the authority when the local run defers).

**Open points a deepen pass must not re-litigate:** locus (ruled C), fail direction (run), exit folding (worst-of), no ADR (all in `decision-challenges.md`).

## Plan Review Revisions

Panel run 2026-10-26: DHH, Kieran, code-simplicity (threshold `none`, so the 3-agent baseline; the CTO already ruled the design, so no separate devex seat). Mechanical findings applied to the plan:

- R1 (Kieran P1) Eligibility is an explicit flag set before the three real exits, never inferred from `mode`; `--self-check` (`finish 0 none ok`) and the adapter `OUT_MODE=full` path were mis-classified by the old mode rule. Rows T11/M10 added.
- R2 (Kieran P1) `AFFECTED_CT_*` initialised in `common.sh`, read with `${...:-0}`, `declare -F` guard; set only after the group validates (finish runs before config load under `set -u`).
- R3 (Kieran P1) Diff parser is an awk state machine (header/path/removal lines can never count), with `--src-prefix/--dst-prefix`, `--no-textconv`, `core.quotePath=false`, tab strip; pattern via `ENVIRON`. Rows T10/T14, M9 added.
- R4 (Kieran P2) `local` `_ct_` variables, no `$(...)` around the scan (scratch registration), no `finish` call from the hook.
- R5 (Kieran P2) Inert path reason becomes `inert-content-trigger`; rc-1 prints a stderr line. rc 6 rule mirrors the delegated arm.
- R6 (Kieran P2) M8 re-pinned to the untracked-leg `grep` consumer (awk cannot raise SIGPIPE); M4 adjacent-line placement; M3 ordered by ledger sequence, not seconds; removal-only, header-with-pattern, space/non-ASCII path, `diff.noprefix`, pure rename and `--base` rows added.
- R7 (Kieran P3) `affected_glob_match` is needed before line 595 for config validation as well as the hook; moved UP inside `affected-tests.sh` (simplicity's in-file reorder) instead of into `common.sh`.
- R8 (Kieran P3) `test_command` explain arm stays silent; contract file line about the marker updated.
- R9 (simplicity P1) One working-tree-vs-merge-base diff plus the untracked leg replaces three tracked legs.
- R10 (simplicity P2/P3) Pattern validation cut to non-empty and no newline; validate folded into `affected_load_config`; path list printed as a count; marker states cut to `clear|ran|failed|skipped|scan-error`; rows T10/T13/T14 merged, M7 and old M10 dropped (see the matrix).
- R11 (DHH P3) The rate measurement is a one-time PR-body note, not a maintained recipe in the contract file.
- R12 (DHH P3) `.claude/hooks/lib/*` dropped from the candidate globs; suite files kept and justified in the glob paragraph.

Taste / not applied (recorded in `decision-challenges.md`): DHH P1 "hard-code a 40-line scan in the plugin script" and "do only the lane widening" (rejected: the plugin ships to other repos and the brief names `affected-tests.sh`; CTO ruled C); DHH P2 duplicated-mechanism (accepted, filed #11166); DHH P2 "do not touch `finish()`" (rejected: `finish()` is the structural chokepoint, see the Guard Contract); DHH P2 / simplicity P1 dedupe of the double run and "cut `--explain`" (double-run accepted per CTO; `--explain` kept as the cheap operator probe and discoverability test).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Make plugins/soleur/scripts/affected-tests.sh select the kb-consumers suite when a new fixture contains knowledge-base/" [issue #10924 P4b + brief] | Phases 1-3 (content-trigger lib, `finish()` hook, config keys, repo config) | mapped |
| 2 | "Resume umbrella #9757, item #10924 P4b only (one PR; P4a is already merged)." [brief] | Non-Goals; single PR | mapped |
| 3 | "PR body uses `Ref #9757` and `Ref #10924` only, never a closing keyword." [brief] | Phase 5 ship step; AC-PR1 | mapped |
| 4 | "Merge with `gh pr merge <N> --squash --auto` through the merge queue, never --admin." [brief] | Phase 5 ship step | mapped |
| 5 | "Do not read or print secrets; do not run doppler or any live credentialed probe." [brief] | Non-Goals; the discoverability probe is local and credential-free | mapped |
| 6 | "Keep apps/** and scripts/registry-restore-from-ghcr.sh unchanged." [brief] | AC-DIFF1 (diff-scope check) | mapped |
| 7 | "Do not close #10924 (tick the P4b checkbox after the merge)." [brief] | Phase 5 post-merge step | mapped |
| 8 | "If the PR edits .github/workflows/apply-web-platform-infra.yml, ask the operator and wait before marking ready or arming the merge." [brief] | AC-DIFF1 (the file is not edited); Phase 5 stop condition | mapped |
| 9 | "Persist every decision as a row of the `\| Item \| Class \| Ruling \|` table in knowledge-base/project/specs/feat-one-shot-10924-p4b-kb-consumers-selection/decision-challenges.md" [brief] | `decision-challenges.md` (created) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `plugins/soleur/scripts/lib/affected-tests/content-trigger.sh` (new) | "select the kb-consumers suite when a new fixture contains knowledge-base/" (ask 1) | asked |
| `plugins/soleur/scripts/lib/affected-tests/common.sh` edit (`finish()` hook, marker field, two moved pure functions) | ask 1 | asked |
| `plugins/soleur/scripts/affected-tests.sh` edit (config keys, validation, header) | "Make plugins/soleur/scripts/affected-tests.sh select" (ask 1) | asked |
| `.soleur-test-gate.json` edit (pattern, paths, command) | ask 1 | asked |
| `plugins/soleur/scripts/affected-tests.test.sh` rows | ask 1; `cq-write-failing-tests-before` | inferred - justification: the gate's contract suite pins every exit and marker path, so an unpinned new path rots silently |
| `plugins/soleur/skills/ship/references/affected-gate-contract.md` edit | ask 1 | inferred - justification: the contract file is the documented config schema and marker grammar that `ship`, `work` and `review` read; a new key and marker field must be there |
| Follow-up issue #11166 | ask 1 | inferred - justification: `wg-when-deferring-a-capability-create-a` requires a tracking issue for the lane gaps found while re-scoping |
| `decision-challenges.md` | ask 9 | asked |

### Split Assessment

- Subsystems touched: 2 - `plugins/soleur/scripts` (gate + lib + contract suite), `plugins/soleur/skills/ship/references` (contract doc) plus one repo-root config file
- Planned files: 7 | Estimated changed lines: about 450 (about 150 lib, about 60 gate edits, about 200 test rows, about 40 docs)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Proposed Solution

### Config keys (flat; all three required together, optional as a group)

| Key | Type | Validation (all failures: rc 4 `bad-config key=<k>`; a vacuous command: `vacuous-test-command`) |
|-----|------|------|
| `content_trigger_pattern` | string | non-empty, no newline; matched as a FIXED string (`index()` / `grep -F`), never a regex |
| `content_trigger_paths` | string[] | non-empty array of non-empty globs, none that matches an arbitrary probe path (`zz9q8/probe.nonexistent` through `affected_glob_match`, the same refusal `inert_paths` has); no default |
| `content_trigger_command` | string | non-empty; refused by `_affected_cmd_vacuous`; run via `bash -c` from the repo root (same trust level as `test_command`, documented) |

Presence rule: any one of the three set without the other two is `bad-config` naming the missing key. Absent group = feature off, marker byte-identical to today. `AFFECTED_CT_ARMED` is initialised to 0 at the top of `common.sh` (next to `AFFECTED_BUDGET_ACTIVE`, never inherited from the environment), read as `${AFFECTED_CT_ARMED:-0}`, and set to 1 only after the whole group validates (`finish()` runs before config load on the usage and help paths, under `set -u`). Validation lives inside `affected_load_config`; there is no separate validate function.

### Mechanism

1. `affected_ct_scan` (new lib `content-trigger.sh`) computes how many changed files under the globs add the pattern. It uses `_ct_`-prefixed `local` variables and returns through globals, never `$(...)` (a subshell would lose the `affected_mktemp` scratch registration and leak the temp file). A mktemp or git failure maps to `scan-error`; the hook never calls `finish`.
   - Base: `--base`, else `origin/main`, else `origin/master` (never `@{upstream}`: on a pushed feature branch it hides every pushed fixture); then `git merge-base <base> HEAD`. No base or no merge-base -> scan-error.
   - Tracked changes: ONE call, `git -c core.quotePath=false diff -U0 --no-color --no-ext-diff --no-textconv -M --src-prefix=a/ --dst-prefix=b/ <merge-base> --` (working tree against the merge-base, which covers committed, staged and unstaged), written to a temp FILE. An `awk` state machine (pattern via `ENVIRON`, passed as `CT_PAT="$pat" awk ...`, never `-v`, which processes escapes) resets on `diff --git`, takes the path from the `+++ b/<path>` header (strip a trailing tab), ignores every `+++`/`---` line until the first `@@` of that file, and counts a `+` line only after that, matching with `index()`. A header or path containing the pattern, or a removal-only hunk, can never fire.
   - Untracked: `git ls-files --others --exclude-standard`, filtered by the globs, then `grep -IlF -- "$pat" <file>` per file (binary skipped; rc 0 match, 1 none, >=2 error), each rc captured on its own line.
   - Every candidate path is filtered through the config globs with `affected_glob_match`. Result states: `none`, `fired` (count only is printed), `scan-error` (any rc outside the allowed set).
2. The hook runs inside `finish()` (the single exit site), before the verdict lines print. Eligibility is an EXPLICIT flag, never inferred from `mode` (`--self-check` ends `finish 0 none ok`, and the adapter path can end `OUT_MODE=full`): `AFFECTED_CT_ELIGIBLE=1` is set immediately before exactly three exits - delegated selected (`affected-tests.sh:489`), inert (`:701`), adapter `rc 0` with `OUT_MODE=selected` (`:903`) - and is initialised to 0 in `common.sh`. The hook runs only when armed, eligible, and `rc` is 0, so `--full`, `test_command`, self-check, explain, help, refusals, budget-deferred and failed primaries never run the command. On `fired` or `scan-error` it runs `affected_bound bash -c "$command"` under the same deadline: command rc 0 keeps `rc 0`; rc 124/137 with `AFFECTED_BUDGET_ACTIVE == 1 && CI_NAME != none` becomes rc 6 `budget-deferred` (mirrors the delegated arm's rule; if the primary run consumed the whole budget `affected_bound` returns 124 at once and a passing primary becomes rc 6, which is the intended CI-authoritative outcome), else rc 1; any other nonzero becomes rc 1, `reason=content-trigger-failed`, and a stderr line (the rc-1 case prints nothing else). On the inert path the reason becomes `inert-content-trigger` so the "docs-only change" line is not printed after the ratchet ran. A primary that ended 1/4/6 skips the command and the marker says `skipped`.
3. `--explain` (kept: it is the cheap operator-facing probe and the discoverability test) prints `CONTENT_TRIGGER armed=1 state=<none|fired|scan-error> paths=<n>` from the delegated and adapter explain exits only (`AFFECTED_CT_EXPLAIN=1` set before `:473` and `:717`; the `test_command` explain arm at `:420` stays silent because `test_command` bypasses selection). It runs nothing. Unarmed prints nothing.
4. Marker: one field appended LAST to the `AFFECTED_GATE ...` line, only when armed: `content_trigger=<clear|ran|failed|skipped|scan-error>` (`scan-error` means the command ran because the scan could not decide; its failure still shows as rc 1). Every existing parser (`gate_field` splits on spaces) keeps working.
5. `affected_glob_match` is moved UP within `affected-tests.sh` (from line ~595 to above the config block, line ~216), definition unchanged. Config validation at `affected_load_config` (line ~370) runs before line 595 today, and the delegated arm exits at line ~489, so a definition at 595 is unreachable for both. The hook (in `common.sh`) resolves it at call time and treats a missing function as `scan-error`. `common.sh` gets no moved function. `affected_resolve_base` is NOT moved: the hook has its own narrower base rule.

### Repo config (this PR)

```json
{
  "budget_seconds": 2400,
  "content_trigger_pattern": "knowledge-base/",
  "content_trigger_paths": ["<final list pinned in Phase 0>"],
  "content_trigger_command": "bash scripts/test-affected-kb-consumers.test.sh"
}
```

Candidate globs (Phase 0 verifies each matches at least one tracked file and re-measures the rate; apps/** tests and markdown are excluded on purpose, see the measured rates):
`tests/*`, `plugins/soleur/test/*`, `plugins/soleur/skills/*/test/*`, `plugins/soleur/scripts/*.test.sh`, `.claude/hooks/*.test.sh`, `scripts/*.test.sh`, `scripts/test-*`. Suite files (`*.test.sh`, `scripts/test-*`) are included on purpose: they are the class the pre-push lane already scans, and the gate (work Phase 2, ship Phase 4) does not. `affected_glob_match` strips every `*/` for its zero-directory retry, so `plugins/soleur/skills/*/test/*` also matches `plugins/soleur/skills/test/x`; harmless over-match, pinned by a test.

Duplicate runs: when the delegated run already selected the ratchet (for example a `knowledge-base/` path also changed) it runs twice, about 91 s extra; accepted in v1 and stated in the contract file (CTO).

## Non-Goals

- No edit to `scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh`, `scripts/pre-push-ratchet-lane.sh`, `apps/**`, `scripts/registry-restore-from-ghcr.sh`, or any `.github/workflows/**` file.
- No widening of the pre-push ratchet lane and no fix of its dead `knowledge-base/` dir entry: #11166.
- No Doppler, secret, or credentialed probe; all verification is local and synthesized.
- No dedupe of the delegated-plus-trigger double run, no array-of-objects config, no regex patterns.

## Deferral Tracking

| Deferred | Why | Re-evaluation | Issue |
|---|---|---|---|
| Lane clause (b) widened to fixtures, `.ts`/`.py` tests, untracked files; dead dir entry in `KB_CONSUMERS_INPUTS` | Different gate; the entry fix is a semantic runner edit that trips lane arm 21 | After this PR measures a false-trigger rate | #11166 (milestone Post-MVP / Later) |
| Dedupe when the delegated run already selected the ratchet | About 91 s on a minority of runs | If measured as a nuisance | recorded here only; no issue (a measurement note in the contract file) |

## Guard Contract

### Guard 1 - the content-trigger hook (`finish()` -> `affected_ct_*`)

**Property.** Whenever a diff adds a line containing the configured fixed string to a file under a configured glob, a passing, non-full run of the gate ends only after the configured command has run (or has been deferred by the budget), and any inability to decide runs the command rather than skipping it.

**Assembly.** The chokepoint is `finish()` in `plugins/soleur/scripts/lib/affected-tests/common.sh`, the one exit site of the gate; every eligible exit (delegated selected at `affected-tests.sh:489`, inert at `:701`, adapter rc 0 with `OUT_MODE=selected` at `:903`) sets `AFFECTED_CT_ELIGIBLE=1` right before calling it, and a future arm is ineligible until it does (fail toward not running a 91 s command; the contract rows fix the three). The population of changed files is the single working-tree-vs-merge-base diff (committed, staged and unstaged) plus the untracked leg, and EVERY file in each, not the first. Explicitly out of the assembly by design: `--full` (also the adapter path ending `OUT_MODE=full`), `test_command` (a full command), help and `--self-check` (which "never runs tests" and ends `finish 0 none ok`), refusals, and rc 1/4/6 primaries (a blocking or deferred result needs no extra run). The config schema is one place (`affected_load_config`); presence of the three keys is validated as a group.

**Mutation matrix.** Derived from the design and written before the code.

| # | Edit that MUST drive the suite RED | Row that catches it |
|---|---|---|
| M1 | Remove the hook call from `finish()` (own dispatch: the feature reports "armed" and checks nothing) | T1 plus the dispatch-floor row asserting the extra-command ledger is non-empty after a firing diff |
| M2 | Make the scan stop after the first compliant (non-matching) file; the matching file is second | T2 (two changed files, first clean, second matches) |
| M3 | REORDER: run the extra command before the primary run completes (hook call at gate start) | T7 (primary fails; ledger must show NO extra call) plus a row observing INSIDE the window: the extra command's ledger line must come AFTER the runner stub's line by ledger sequence number (not `date +%s`, which has 1 s granularity) |
| M4 | Scan whole files, or widen the diff context (`-U3`), instead of added lines | T4 (pattern already present; an unrelated line added ADJACENT to it, so a context-line mutation also fires; must not fire) |
| M5 | Flip the fail direction: scan error skips instead of running | T5 (no resolvable base: must run and print `content_trigger=scan-error`) |
| M6 | Ignore the extra command's rc | T6 (command exits 1: gate exit must be 1) |
| M7 | Replace the untracked-leg `grep -IlF` over a temp file with `producer \| grep -q` under pipefail | T9 (an untracked set whose output exceeds the 64 KB pipe buffer, matching path sorted first, must still fire; awk reads to EOF and cannot raise SIGPIPE, so this row targets the grep consumer only) |
| M8 | Drop the untracked leg | T3 (new untracked file containing the pattern) |
| M9 | Treat a `+++ b/<path>` header, or a removal (`-`) line, as an added line | T10 (a path containing the pattern, and a removal-only hunk, must not fire) |
| M10 | Infer eligibility from `mode` instead of the explicit flag | T11 (`--self-check` and `--explain` while armed: empty ledger) |

**Harness rows.** (H1) Delete the stub's ledger write: every "ran" row must go RED (the ledger self-test from the suite's instrument-fidelity rule). (H2) A must-PASS row that is NOT the canonical shape: a different pattern (`zz-marker/`), different globs (`src/*`), and a different command stub still fires, proving nothing is hard-coded to this repo; the T8 row (a changed file outside the globs must not fire) pins the glob scope. (H3) A must-PASS row for the unarmed gate: the `AFFECTED_GATE` line is byte-identical to the pre-change line.

**Anchor.** The stored value is the repo config, which a PR can edit together with the code; the guard proves consistency, not integrity. The independent anchor is CI: the `merge_group` full battery runs the ratchet on the candidate tree (ADR-276), and the contract suite's live-repo row asserts the committed config arms the trigger with the expected command, so weakening it in a later PR reddens that row unless the PR edits the row too.

**Validated against the post-change tree.** The remediation writes new test rows and docs that themselves mention the pattern; the new rows string-join the literal, and the ratchet plus the explicit pre-push list below run on the final tree (not the tree this plan was written against).

## User-Brand Impact

- **If this lands broken, the user experiences:** no end-user surface; the developer running the gate sees a wrong exit code (a false red from the extra command, or a missed ratchet that CI then reddens in the merge queue).
- **If this leaks, the user's data is exposed via:** no vector; the gate reads diffs and runs a repo-declared command, handles no credentials, and prints only sanitized path names.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** `none` - developer-tool selection logic with CI as the independent backstop; `aggregate pattern` would only apply if a false negative could ship a product defect, which a ratchet miss cannot.

*Scope-out override:* threshold: none, reason: plugins/soleur/scripts is local developer tooling and the repo-root gate config carries only a selection string and a repo-relative command; neither touches user data, auth, or money.

## Observability

```yaml
liveness_signal:
  what:            "AFFECTED_GATE marker line gains content_trigger=<state> on every armed run; --explain prints CONTENT_TRIGGER armed=1"
  cadence:         "per gate run (work Phase 2, ship Phase 4, review, grok-pre-push-gate)"
  alert_target:    "the invoking agent/operator terminal; the skills already branch on the gate's rc"
  configured_in:   "plugins/soleur/scripts/lib/affected-tests/common.sh (finish) and .soleur-test-gate.json"

error_reporting:
  destination:     "stderr and the AFFECTED_GATE marker of the gate itself (a local CLI, no Sentry project)"
  fail_loud:       "rc 1 reason=content-trigger-failed with the command's output, or rc 4 bad-config key=<k> on a malformed trigger config"

failure_modes:
  - mode:          "scan cannot decide (git error, no base)"
    detection:     "marker content_trigger=scan-error-ran and a stderr line naming the leg"
    alert_route:   "the invoking terminal; the command still runs"
  - mode:          "trigger never fires on a real new fixture (silent miss)"
    detection:     "contract-suite rows T1/T2/T3/T9 and the dispatch-floor row (extra-command ledger non-empty after a firing diff); CI merge_group full battery runs the ratchet regardless"
    alert_route:   "red contract suite in CI, red merge queue"
  - mode:          "false-trigger rate climbs above 10 percent of commits"
    detection:     "the Phase 0 measurement (command and figure recorded in the PR body); re-run by whoever changes content_trigger_paths"
    alert_route:   "narrow content_trigger_paths in a follow-up PR (CTO flip evidence)"

logs:
  where:           "gate stdout/stderr in the invoking session; no persistent log"
  retention:       "session scrollback"

discoverability_test:
  command:         bash plugins/soleur/scripts/affected-tests.sh --explain
  expected_output: CONTENT_TRIGGER armed=1
```

## Implementation Phases

### Phase 0 - RED first and measurement (`cq-write-failing-tests-before`)

1. Add the contract-suite rows T1-T15 (below) to `plugins/soleur/scripts/affected-tests.test.sh` against fixture repos with stub runners; run once and confirm RED for the right reason (no hook yet).
2. Pin `content_trigger_paths`: verify each candidate glob matches at least one tracked file (`git ls-files | grep` translation), re-run the 150-commit rate measurement for the final set, record the figure in the PR body; if above 10 percent, drop globs until at or under.

### Phase 1 - the lib

3. Create `plugins/soleur/scripts/lib/affected-tests/content-trigger.sh`: `affected_ct_scan` and `affected_ct_run` (every variable `local` with a `_ct_` prefix, results through globals, no `$(...)` around the scan); no `declare -A`, no `mapfile`, `${arr[@]+"${arr[@]}"}` under `set -u`, no `sed -i`, `date -d`, `readlink -f`, `stat -c` (the portability contract the suite already asserts). Capture every rc on its own line.
4. Edit `common.sh`: initialise `AFFECTED_CT_ARMED=0`, `AFFECTED_CT_ELIGIBLE=0`, `AFFECTED_CT_EXPLAIN=0` next to `AFFECTED_BUDGET_ACTIVE`; add the `finish()` hook (guarded by `declare -F` and `${...:-0}` reads) and the marker field. The unarmed path must not change a byte.

### Phase 2 - config and gate wiring

5. Edit `affected-tests.sh`: source the new lib; move `affected_glob_match` up above the config block; parse and validate the three keys in `affected_load_config` (group presence rule, glob probe, vacuous command); set `AFFECTED_CT_ELIGIBLE=1` / `AFFECTED_CT_EXPLAIN=1` immediately before the delegated (`:489`, `:473`), inert (`:701`) and adapter (`:903`, `:717`) exits only; update the header's key list and exit-contract comment.
6. Edit `.soleur-test-gate.json` with the three keys.

### Phase 3 - docs

7. Edit `affected-gate-contract.md`: three config rows, the `content_trigger=` marker field, the order of evaluation, the double-run note, the trust note (command runs like `test_command`), the rate-measurement recipe.

### Phase 4 - verify (local, bounded, no credentials)

8. `bash plugins/soleur/scripts/affected-tests.test.sh`; then the repo-global ratchets that a file query does not select, explicitly: `plugins/soleur/test/fixture-relative-assert.test.sh`, `fixture-dir-operand-assert.test.sh`, `fixture-cd-containment.test.sh`, `fixture-env-adoption`, `guard-vacuity-floor`, `scripts/test-affected-kb-consumers.test.sh` (never treat a local `SKIP reason=no-trigger` as evidence), `scripts/lint-orphan-test-suites.sh`, `scripts/workflow-run-deploy-invariants` equivalents named in the 2026-10-14 learning. Confirm `bash scripts/test-all.sh --print-selection` still reports `fallback=none` for this diff (no runner edit): the gate suite is selected through its declared edge on `plugins/soleur/scripts/lib/affected-tests/`.
9. Dogfood: add a synthesized fixture file with a string-joined pattern line in a scratch worktree path, run `bash plugins/soleur/scripts/affected-tests.sh --explain` and confirm `CONTENT_TRIGGER armed=1 state=fired`; do not run the full gate with credentials.

### Phase 5 - ship (headless pipeline)

10. PR body: `Ref #9757`, `Ref #10924`, no closing keyword; `## Changelog` section; link #11166. If the diff shows `.github/workflows/apply-web-platform-infra.yml`, stop and ask the operator before marking ready. Merge: `gh pr merge <N> --squash --auto` through the merge queue, never `--admin`. After the merge, tick the P4b checkbox on #10924 and leave it open.

## Files to Create

- `plugins/soleur/scripts/lib/affected-tests/content-trigger.sh`
- `knowledge-base/project/specs/feat-one-shot-10924-p4b-kb-consumers-selection/decision-challenges.md` (created)
- `knowledge-base/project/specs/feat-one-shot-10924-p4b-kb-consumers-selection/tasks.md`

## Files to Edit

- `plugins/soleur/scripts/affected-tests.sh`
- `plugins/soleur/scripts/lib/affected-tests/common.sh`
- `plugins/soleur/scripts/affected-tests.test.sh`
- `plugins/soleur/skills/ship/references/affected-gate-contract.md`
- `.soleur-test-gate.json`

## Open Code-Review Overlap

None. (Queried open `code-review` issues for each file above on 2026-10-26: no matches.)

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO agent ruled the locus, trigger shape, fail direction, exit folding and ADR question on 2026-10-26 (rows in `decision-challenges.md`). Biggest named risk: selection logic is now split across two layers (the runner's `--print-selection` and CI's replay mirror will not show a gate-added run); mitigated by CI `merge_group` as the backstop and by the marker field. No Product/UX surface (no user-facing page or component), so no wireframe gate.

## Architecture Decision (ADR/C4)

No ADR and no C4 change, per the CTO ruling: the plan adds a config-declared step to a local developer gate, adds no service, substrate or data boundary, and reverses no ADR (ADR-242 decisions 19/22 and the runner are untouched). C4 completeness check: external actors/systems (none new), data stores (none), actor-to-surface access relationships (none changed); `plugins/soleur/test/c4-count-parity.test.sh` is not expected to move because no workflow, monitor or heartbeat count changes.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC-1 `bash plugins/soleur/scripts/affected-tests.test.sh` exits 0 with the new rows T1-T15 present and each mutation M1-M10 demonstrated RED by hand once (recorded in the PR body).
- [ ] AC-2 With the repo config, a synthesized new test-tree file containing the string-joined pattern makes `bash plugins/soleur/scripts/affected-tests.sh --explain` print `CONTENT_TRIGGER armed=1 state=fired`, and a diff without it prints `state=none`.
- [ ] AC-3 An unarmed gate prints an `AFFECTED_GATE` line byte-identical to the pre-change line (row H3).
- [ ] AC-4 `bash scripts/test-affected-kb-consumers.test.sh` exits 0 with no new baseline row; every new test row spells the literal string-joined.
- [ ] AC-5 The measured trigger rate for the final `content_trigger_paths` is at or under 10 percent of the last 150 first-parent non-merge commits, and the PR body states the number and the command.
- [ ] AC-6 `AC-DIFF1`: `git diff --name-only origin/main...HEAD` lists nothing under `apps/`, nothing named `scripts/registry-restore-from-ghcr.sh`, nothing under `.github/workflows/`, and neither `scripts/test-all.sh` nor `scripts/lib/test-affected-paths.sh`; `bash scripts/test-all.sh --print-selection` (cold derive takes more than 10 minutes in this checkout: run it detached, bounded, output to a file) reports `fallback=none` for the diff. The diff-scope checks use the merge-base form `git diff --name-only origin/main...HEAD`, never `origin/main` alone.
- [ ] AC-7 `plugins/soleur/skills/ship/references/affected-gate-contract.md` documents the three keys, the marker field, the order of evaluation, the double-run note and the trust note.
- [ ] AC-PR1 The PR body carries `Ref #9757` and `Ref #10924` and no closing keyword; merge is `gh pr merge <N> --squash --auto` via the queue.

### Post-merge (operator-free)

- [ ] AC-POST1 The P4b checkbox on #10924 is ticked and the issue is left open (P4c, P4d remain).

## Test Scenarios

Every marker row pins the WHOLE `AFFECTED_GATE ...` line (including the appended `content_trigger=` field), not a substring; the field is exercised with count 0 (`clear`), 1 and 2 changed matching files, and one fixture with an allowlisted look-alike (a file under the globs that only names the pattern in a removed line).

Fixture-repo rows in `plugins/soleur/scripts/affected-tests.test.sh` (synthesized repos, stub delegated runner that logs to a ledger; every "ran" claim is asserted against the ledger, never an exit code alone; the pattern literal is string-joined in the suite text):

| ID | Scenario | Expected |
|----|----------|----------|
| T1 | A committed file under a glob adds a line with the pattern (delegated runner stub) | extra command in ledger, rc 0, `content_trigger=ran` |
| T2 | Two changed files; the first has no pattern, the second does | fires (M2) |
| T3 | New untracked file with the pattern | fires |
| T4 | Existing file already contains the pattern; an unrelated line is added next to it | does not fire (M4) |
| T5 | No resolvable base (no origin/main) | extra command runs, `content_trigger=scan-error` |
| T6 | Extra command exits 1 | gate rc 1, reason `content-trigger-failed`, stderr line |
| T7 | Primary run fails (runner stub rc 1); and a passing primary | failed: extra command NOT in ledger, marker `skipped`; passing: extra after runner by ledger sequence (M3) |
| T8 | Pattern added in a file outside the globs | does not fire |
| T9 | Untracked set larger than the pipe buffer, matching path first | fires (M7) |
| T10 | Pattern only in a path name or a `-` removal line; a pure rename with no added line | does not fire (M9) |
| T11 | `--self-check` and `--explain` while armed; `--full`; a failing primary | empty ledger (M10); `--explain` prints `CONTENT_TRIGGER armed=1 state=<...>`, the `test_command` explain arm prints nothing |
| T12 | Budget expires during the extra command with a CI workflow; and with none | rc 6; rc 1 |
| T13 | Config errors: one or two of three keys; empty paths; match-everything glob; vacuous command; pattern with newline; wrong types | rc 4 `bad-config key=<k>` / `vacuous-test-command` |
| T14 | A path with a space and a non-ASCII character; `diff.noprefix=true` in the fixture repo config; delegated `--base X` | fires; the hook honours `--base` while the runner stub ignores it (documented) |
| T15 | Live-repo row: committed `.soleur-test-gate.json` validates and `--explain` prints `CONTENT_TRIGGER armed=1`; the inert path after the command ran does not print the "docs-only change" line | green |
| H1 | Delete the stub ledger write | every "ran" row goes RED |
| H2 | Different pattern/globs/command | fires (nothing hard-coded) |
| H3 | Unarmed config | marker line byte-identical |

## Dependencies & Risks

- **Selection split across two layers (named by the CTO).** The runner's `--print-selection` and CI's replay mirror will not show the gate-added run. Mitigation: the marker field, `--explain`, and CI `merge_group` running the ratchet on the candidate tree.
- **Config string runs as a command.** Same trust level as `test_command`; a PR can edit the config and the code together (consistency, not integrity); CI is the independent gate.
- **False-trigger rate.** Path-limited, added-lines-only, fixed-string; measured 7.3 percent for the test trees; `scripts/**` whole-tree was 10.7 percent and is not used. Flip evidence: above 10 percent, narrow the globs.
- **Local gate queueing.** The 2026-10-22 session sat 40+ minutes behind its own stale runs; use `list_runs` / `kill_mine` from `plugins/soleur/scripts/lib/proc.sh` before a gate run, and treat CI as authoritative on `AFFECTED_GATE_BUDGET_DEFERRED`.
- **Moving `affected_glob_match` up within `affected-tests.sh`.** A pure-function reorder; the existing `inert_paths` probe rows pin it. The hook calls it at run time and treats a missing definition as `scan-error`.
- **Dynamic scoping inside `finish()`.** Helpers called from it see its locals (`rc`, `mode`, `reason`); the hook uses `_ct_`-prefixed `local` variables only.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; it is filled here.
- `finish()` must keep a single exit site: do not add a second `exit` in the hook, and keep `rc` folding inside `finish` so the marker is written once.
- `awk -v pat=...` processes backslash escapes; pass the pattern through `ENVIRON`.

## References

- Issue #10924 (P4b row), umbrella #9757, draft PR #11164, follow-up #11166.
- `plugins/soleur/scripts/affected-tests.sh`, `plugins/soleur/scripts/lib/affected-tests/common.sh`, `plugins/soleur/skills/ship/references/affected-gate-contract.md`.
- `scripts/pre-push-ratchet-lane.sh` (`conditional_reason`, prior art), `scripts/test-affected-kb-consumers.test.sh`, `scripts/lib/test-affected-paths.sh`.
- ADR-242 (decisions 19, 20, 22), ADR-276 (decision 5).
- Learnings: 2026-10-01 grep-q pipefail; 2026-10-14 ratchets no file query selects; 2026-10-22 hop-regex and stale runs.
