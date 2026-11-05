---
title: "ci: affected-index-ratchet fails every PR with stale-accept (main-side anchor drift)"
type: fix
date: 2026-11-05
slug: fix-affected-ratchet-stale-accept
branch: feat-one-shot-12110-accept-anchor-repin
issue: 12110
closes: 12110
priority: high
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# ci: affected-index-ratchet fails every PR with stale-accept (main-side anchor drift)

Spec lacks valid `lane:` (no spec.md exists for this branch) — defaulted to cross-domain (TR2 fail-closed).

## Overview

The advisory `affected-index-ratchet` job (`.github/workflows/ci.yml:417`) fails on
every PR with `SOLEUR_PR_AFFECTED_RATCHET exit=1 reason=stale-accept` because rows in
`scripts/ci-pr-affected-audit.accept.tsv` are stale relative to the live tree. The fix
is oracle-data repair only: delete the 11 stale accept rows the current report flags,
and drain the 3 live `new-pair` findings per the script's own remedies (a declared
edge only when the suite really reads the file; an anchor-keyed accept row when it
merely names it). No script, workflow, or test logic changes.

**Corrections to the issue body** (verified locally against origin/main `f06b595420`,
worktree at `988f64e185`):

1. The `anchor` column is **not** a git SHA — it is the first 12 hex of sha256 over
   `" ".join(line.split())` of the comment-stripped source line as written
   (`scripts/ci-pr-affected-replay.py:125`). The issue's `git log -1 --format=%H`
   re-pin recipe is wrong; correct anchors come from the script's own `ref` output
   lines (`audit --all-refs` or the ratchet report).
2. The two rows the issue names are no longer flagged — main drifted and the current
   red set is the 11 stale rows + 3 new-pairs enumerated below.

**Sibling coordination:** PR #12103 (`feat-one-shot-12013-12025-affected-gate-reprice`,
draft, live session) touches only KB artifacts (ADR-242, plan/spec files,
measurements) — verified via `gh pr view 12103 --json files`; it does not touch
`accept.tsv` or `test-affected-paths.sh`. Landing this fix unblocks its failing
ratchet runs. Do not duplicate its scope or edit that PR.

## User-Brand Impact

- **If this lands broken, the user experiences:** continued or new red on the advisory
  `affected-index-ratchet` check across every open PR (operator-visible CI noise and
  merge-queue confusion); worst case, a wrong accept row masks a real read the
  selector should know about (a false negative on suite selection).
- **If this leaks, the user's [data / workflow / money] is exposed via:** no user data
  or workflow surface — the diff is CI oracle data (exemption rows / a declared edge)
  inside repo-internal test-selection machinery.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** no user-facing artifact changes; the blast
  radius is internal CI signal quality, which lands on repo maintainers, not end users.

## Research Insights

### Premise Validation

- `gh issue view 12110`: **OPEN**, title as above, no closing PR. Premise holds.
- All cited paths exist on `origin/main`: `scripts/ci-pr-affected-audit.accept.tsv`,
  `scripts/ci-pr-affected-replay.py`, `.github/workflows/ci.yml`,
  `plugins/soleur/test/components.test.ts`, `scripts/sentry-issue.sh`,
  `scripts/betterstack-query.sh`.
- **Reproduced in the worktree** (2026-11-05):
  `python3 -I scripts/ci-pr-affected-replay.py ratchet --report /tmp/ratchet-report.txt`
  → `exit=1 reason=stale-accept live=3 baseline=0`, flagging exactly the 11
  stale-accept rows and 3 new-pair findings enumerated below.
- `scripts/ci-pr-affected-audit.baseline.tsv` exists and is **empty (0 bytes)** —
  baseline state is "present at both" → the live pair set must equal it, i.e.
  `live=0` is the pass condition.
- **Collision pre-check** (`collision-precheck.sh 12110`): PR #12128 is *this* branch's
  own pipeline-created draft — not a duplicate. Foreign `test-all.sh` processes belong
  to sibling live worktrees (`feat-one-shot-10390-ci-hygiene-batch`,
  `feat-one-shot-12013-12025-affected-gate-reprice`) — reported, not blocking.
- **ADR corpus:** ADR-242 (affected-gate + always-on ratchets; the selector grammar and
  `glob:` semantics) and ADR-290 (anchor = first 12 hex of sha256 of the
  whitespace-normalised line — same anchor construction, confirms the semantics).
  No ADR rejected the planned mechanism; this is a data repair inside machinery ADR-276's
  amendment ratified.

### Mechanism Minimality (Phase 0.6b)

**Property list:** (P1) the ratchet exits 0 on a tree whose diff touched neither the
suites nor the named paths — no `stale-accept`, no `new-pair` on the current tree.
(P2) the fix is durable against routine churn of the anchor lines. (P3) no selection-
behavior regression (a merely-named file must not become a real read edge).

**Cut list:**

| Mechanism the issue proposes | Property | Verdict |
|---|---|---|
| "Re-pin the stale accept rows' anchor SHAs to the commits that last touched the referenced files" | P1 | **Cut — impossible as stated.** Anchors are content sha256 prefixes, not git SHAs; `stale-accept` remedy is delete-only ("the tree no longer backs it"). |
| "Regenerate the accept file" | P1 | **Cut — no such command exists.** `ratchet --print-baseline` is prune-only and writes the *baseline*, never accept rows. Accept rows are hand-authored per boundary line from `audit --all-refs`. |
| Per-row delete/add per the script's own remedies | P1, P2 | **Adopted** — the only mechanism that satisfies P1 without new machinery. |

### The flagged set (complete enumeration — `ratchet --report`, worktree, 2026-11-05)

**A. `stale-accept` — 11 rows to delete** (remedy: "delete the accept row: the tree no
longer backs it, or it is malformed"):

| accept.tsv line | suite | path | anchor/ordinal | why |
|---|---|---|---|---|
| 355 | `plugins/soleur` | `apps/web-platform/scripts/plugin-root-sandbox-propagation-probe.mjs` | `4663b0253b8d/1` | not-a-gap |
| 356 | `plugins/soleur` | `apps/web-platform/scripts/plugin-root-sandbox-propagation-probe.mjs` | `4e5a4d1caf27/1` | not-a-gap |
| 357 | `plugins/soleur` | `apps/web-platform/scripts/sandbox-canary.mjs` | `0ce179c2ca7a/1` | not-a-gap |
| 358 | `plugins/soleur` | `apps/web-platform/scripts/sandbox-canary.mjs` | `3be5ad93bfce/1` | not-a-gap |
| 359 | `plugins/soleur` | `apps/web-platform/scripts/sandbox-canary.mjs` | `da9456338a93/1` | not-a-gap |
| 360 | `plugins/soleur` | `apps/web-platform/scripts/sandbox-canary.mjs` | `db12ad216e7d/1` | not-a-gap |
| 361 | `plugins/soleur` | `apps/web-platform/scripts/sandbox-canary.mjs` | `df729b3e38c7/1` | not-a-gap |
| 362 | `plugins/soleur` | `apps/web-platform/scripts/sandbox-canary.mjs` | `fa71562066a9/1` | not-a-gap |
| 369 | `plugins/soleur` | `package.json` | `0b403e085b16/1` | anchor-not-live |
| 374 | `plugins/soleur` | `package.json` | `8d47cc95bf11/1` | anchor-not-live |
| 383 | `plugins/soleur` | `package.json` | `f3792010002b/1` | anchor-not-live |

The three `package.json` rows are `anchor-not-live`: the pair is still a live gap but
the remaining ~11 sibling rows (`accept.tsv:370-383` minus the flagged three) still
cover every live boundary line — verified via `judge_rules` semantics
(`scripts/ci-pr-affected-replay.py:1591-1621`); the pair does NOT appear in the
new-pair list, so deleting only the three dead rows keeps it fully accepted. The
eight `.mjs` rows are `not-a-gap`: `plugins/soleur/test/model-launch-review.test.ts`
no longer names those paths (or an edge now declares them), so the pairs are not gaps.

**B. `new-pair` — 3 live pairs to drain** (cause: "your change touched neither … —
main is already red for this pair, or a covering edge was removed"). All six boundary
lines live in `plugins/soleur/test/components.test.ts`:

| suite | path | boundary lines (from `ref` lines) | disposition |
|---|---|---|---|
| `plugins/soleur` | `scripts/sentry-issue.sh` | `:989` `ee8220c7499a/1`, `:992` `b50d46d45247/1` | **declare edge** (below) |
| `tests/hooks/emissions` | `scripts/betterstack-query.sh` | `:987` `6e9e24010f9b/1`, `:992` `b50d46d45247/1` | **accept rows ×2** |
| `tests/hooks/emissions` | `scripts/sentry-issue.sh` | `:989` `ee8220c7499a/1`, `:992` `b50d46d45247/1` | **accept rows ×2** |

### Disposition evidence (declare-vs-accept is per-pair, per the runbook)

`components.test.ts:987-992` names the two scripts only inside `toEqual` expected
literals — the test extracts `Vendor through wrapper` phrases and shell-wrapper
paths from a **doc** and asserts equality against literals; it never reads
(`readFileSync`), executes, or stats `scripts/sentry-issue.sh` / `scripts/betterstack-query.sh`
(verified: `grep` for read/exec of those paths returns only the three literal lines).
The files' state does not feed the verdict — a rename or edit of either script cannot
change the test result. Both pairs are "the suite merely names the file".

- **`plugins/soleur` arm — declared edge (assumed; technical fork recorded).**
  `AFFECTED_PLUGINS_SOLEUR_PATHS` already carries four sibling *mention-pair* globs —
  `"glob:scripts/*betterstack-query.sh"` at `scripts/lib/test-affected-paths.sh:1306`
  (the sibling script in the same assertion block) plus `:1307-1309` — each justified
  "every boundary line anchored on >8-commits/90d file — accept rows refused".
  `components.test.ts` is at **26 commits/90d** (`git log --since=90.days`), over the
  in-tree criterion, and the vendor-list assertion block (`components.test.ts:968-1000`,
  added 2026-11-04 by #12061) is designed to grow per vendor — the single-line array at
  `:992` is edited by any vendor addition, which would re-stale accept-row anchors and
  reproduce this issue on an unrelated PR. Install
  `"glob:scripts/*sentry-issue.sh"  # mention pair; every boundary line anchored on >8-commits/90d file — accept rows refused`
  in member-string order (after `glob:scripts/*prod-version-drift-b9-probe.sh`,
  before `glob:tests/scripts/...`). Narrow per-pair globs never join the naming walk —
  reveal-free by construction (pr5d ruling).
- **`tests/hooks/emissions` arm — 4 accept rows (assumed).** The suite's convention is
  accept rows for `components.test.ts` mentions: it carries 10 live rows
  (`accept.tsv:2745-2754`) citing `test_hook_emissions.sh:161`, which passes
  `components.test.ts` only inside a synthetic `git stash && bun test ...` command
  string to `guardrails.sh` — the suite never executes or reads it (verified
  `tests/hooks/test_hook_emissions.sh:161`). New rows use the closed kind grammar
  `false-positive: fixture or assertion label: <file:line>: <evidence>` and are inserted
  in C-locale sorted position among the `tests/hooks/emissions` block.

**Fork recorded** (`decision-challenges.md`): uniform-accept-rows vs
uniform-narrow-globs vs the per-suite-convention split above — `pending - assumed:
split` for the parent's CTO ruling. All three arms are mechanically enumerated so
either ruling is executable.

### `oracle-inputs-changed` behavior on the fix PR itself

`ratchet_oracle` (`scripts/ci-pr-affected-replay.py:1898`, `RATCHET_ORACLE` at `:1755`)
prints `oracle-inputs-changed: <files>` — **non-blocking, a notice never a verdict** —
when the diff to base touches the oracle set: `ci.yml`, the replay script,
`lint-ratchet.py`, **the accept file**, `test-affected-paths.sh`, `test-all.sh`, or the
baseline. Our diff touches `accept.tsv` (+ `test-affected-paths.sh` under the assumed
arm) → the notice prints; `ci.yml:453` emits a `::warning` annotation; the job still
exits 0 once `live=0`. "A new accept row is therefore announced, and is the drain tool,
not a verdict" (`:164`). The issue's premise holds: the path is designed for oracle
edits — it announces them for human review rather than passing them silently.

### Institutional learnings applied

- `2026-11-03-one-malformed-accept-row-reason-drops-every-exemption.md` — col 5 must
  start `false-positive:` plus a space (one malformed row drops ALL exemptions via
  `load_accept` → `accept={}` → pair flood). Plan validates with `audit --accept` +
  `awk -F'\t' 'NF==5 && $5 !~ /^false-positive: /'` before the final ratchet run.
- `test-failures/2026-10-30-audit-accept-rows-need-every-boundary-line-...md` — build rows from
  `audit --all-refs`, never the ratchet report (its ref display caps at ~3 per pair;
  a pair exempts only when EVERY boundary line has a row). Our report shows ≤2 refs
  per pair — `--all-refs` confirms completeness before writing.
- `2026-11-01-ratchet-repair-pair-disposition-...md` — one real-read boundary line
  makes the whole pair a declared edge; the SUT-source boundary line decides.
  Checked: all six boundary lines are `toEqual` literals — no real reads.
- `2026-10-26-a-ratchet-green-on-the-branch-tip-was-red-on-the-merged-tree.md` —
  anchor-keyed rows go stale on sibling merges; **re-run the ratchet after every
  rebase/merge**, and verify on the merged tree before arming (merge queue entries
  run on the merged tree).
- `2026-10-31-accept-row-reasons-must-enumerate-real-tree-read-arms.md` — "never reads"
  reasons must enumerate real-tree arms / cite the always-on twin; reasons drafted
  accordingly with the `:161` evidence line.
- `feat-one-shot-10861-pr5d-sweeps` (merged into this merge base as `f06b595420`,
  PR #12116) — deleted 11 `plugins/soleur` mention rows on a 111-commits/90d anchor
  file and installed narrow `dir`-class globs; the freshest in-tree disposition for
  this pair class.
- Community-discovery / functional-overlap check: repo-internal CI-oracle data repair —
  no external skill can cover it; no Task-spawn capability in this subagent; skipped.

### Related issues/PRs

- #12110 (this fix), PR #12128 (this branch's draft).
- PR #12103 `feat-one-shot-12013-12025-affected-gate-reprice` — adjacent machinery,
  KB-only diff, unblocked by this fix; not edited.
- #10448 — the S4 index-completion epic owning this check (report defects there if the
  selector/audit itself misbehaves).
- Runbook: `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md`
  §"Ratchet red on a PR or queue entry" — the remedy table this plan applies.

## Files to Edit

- `scripts/ci-pr-affected-audit.accept.tsv` — delete the 11 stale rows enumerated in
  table A; add the 4 `tests/hooks/emissions` rows enumerated in table B (assumed arm).
- `scripts/lib/test-affected-paths.sh` — insert one `"glob:scripts/*sentry-issue.sh"`
  member in `AFFECTED_PLUGINS_SOLEUR_PATHS` (member-string order, sibling-comment style)
  — **only under the assumed edge arm**.

## Files to Create

- None.

## Implementation Phases

### Phase 1 — Enumerate the live boundary set

1. Re-run `python3 -I scripts/ci-pr-affected-replay.py ratchet --report <report>` in the
   worktree and diff the flagged set against tables A/B — if main drifted further,
   re-enumerate (every flagged row gets a disposition; none silently dropped).
2. Run `python3 -I scripts/ci-pr-affected-replay.py audit \
   --accept scripts/ci-pr-affected-audit.accept.tsv --all-refs | grep '^ref'` and confirm
   the complete boundary-line set for the 3 pairs (the ratchet report caps the per-pair
   ref display). If `--all-refs` reveals boundary lines beyond the six table-B refs,
   each gets its own row/edge coverage in the same commit.

### Phase 2 — Apply the dispositions

3. Delete the 11 stale-accept rows from `scripts/ci-pr-affected-audit.accept.tsv`
   (exact-line deletes; keep C-locale sort order and the trailing newline intact).
4. `plugins/soleur` pair: add `"glob:scripts/*sentry-issue.sh"` to
   `AFFECTED_PLUGINS_SOLEUR_PATHS` in member-string order with the sibling justification
   comment (`# mention pair; every boundary line anchored on >8-commits/90d file —
   accept rows refused`). *(If the parent rules the accept-row arm instead: two rows
   `plugins/soleur<TAB>scripts/sentry-issue.sh<TAB>{ee8220c7499a,b50d46d45247}<TAB>1<TAB>false-positive: fixture or assertion label: plugins/soleur/test/components.test.ts:{989,992} pins the literal inside a toEqual array; the suite never reads or executes the script`.)*
5. `tests/hooks/emissions` pairs: add the 4 accept rows below, inserted in C-locale
   order inside the `tests/hooks/emissions` block:

   (columns shown with `<TAB>` markers — write real tab characters):

   ```text
   tests/hooks/emissions<TAB>scripts/betterstack-query.sh<TAB>6e9e24010f9b<TAB>1<TAB>false-positive: fixture or assertion label: plugins/soleur/test/components.test.ts:987 pins the literal 'Better Stack=scripts/betterstack-query.sh' inside a toEqual array of <Vendor> through <wrapper> phrases extracted from a doc; test_hook_emissions.sh:161 only passes components.test.ts inside a synthetic 'git stash && bun test ...' command string to guardrails.sh — the suite never reads or executes scripts/betterstack-query.sh
   tests/hooks/emissions<TAB>scripts/betterstack-query.sh<TAB>b50d46d45247<TAB>1<TAB>false-positive: fixture or assertion label: plugins/soleur/test/components.test.ts:992 pins the literal inside a toEqual array of shell-wrapper paths; same synthetic-command-string reach (test_hook_emissions.sh:161) — the suite never reads or executes scripts/betterstack-query.sh
   tests/hooks/emissions<TAB>scripts/sentry-issue.sh<TAB>ee8220c7499a<TAB>1<TAB>false-positive: fixture or assertion label: plugins/soleur/test/components.test.ts:989 pins the literal 'Sentry=scripts/sentry-issue.sh' inside the same toEqual array; same synthetic-command-string reach (test_hook_emissions.sh:161) — the suite never reads or executes scripts/sentry-issue.sh
   tests/hooks/emissions<TAB>scripts/sentry-issue.sh<TAB>b50d46d45247<TAB>1<TAB>false-positive: fixture or assertion label: plugins/soleur/test/components.test.ts:992 pins the literal inside the same toEqual array; same synthetic-command-string reach (test_hook_emissions.sh:161) — the suite never reads or executes scripts/sentry-issue.sh
   ```

   *(If the parent rules the uniform-glob arm instead: add
   `"glob:scripts/*betterstack-query.sh"` and `"glob:scripts/*sentry-issue.sh"` to
   `AFFECTED_TESTS_HOOKS_EMISSIONS_PATHS` with the same justification comment and drop
   the four rows.)*

### Phase 3 — Verify the fixpoint

6. Validate the accept file parses: `awk -F'\t' 'NF==5 && $5 !~ /^false-positive: /'
   scripts/ci-pr-affected-audit.accept.tsv'` prints nothing, and
   `python3 -I scripts/ci-pr-affected-replay.py audit \
   --accept scripts/ci-pr-affected-audit.accept.tsv` exits 2-free of parse errors
   (a `ValueError` there drops every exemption — the 2026-11-03 flood class).
7. `python3 -I scripts/ci-pr-affected-replay.py ratchet --report <report>` →
   `SOLEUR_PR_AFFECTED_RATCHET exit=0 reason=pass live=0 baseline=0`; an
   `oracle-inputs-changed:` line naming `accept.tsv` (and `test-affected-paths.sh`
   under the edge arm) is expected and non-blocking. **Iterate to the fixpoint** — if a
   new flag appears, repeat Phase 1's enumeration.
8. After any rebase or merge before arming, re-run step 7 on the merged state (sibling
   merges can stale anchors without a textual conflict — the merged-tree learning).

## Observability

Skipped per plan Phase 2.9 detection: `## Files to Edit` contains no code-class file
under `apps/*/server/`, `apps/*/src/`, `apps/*/infra/` or `plugins/*/scripts/` and
introduces no new infrastructure surface — the diff is data rows in an existing CI
oracle (plus one edge member under the assumed arm). The observable remains the
check's own marker line (`SOLEUR_PR_AFFECTED_RATCHET exit=…`), the `::error`/
`::warning` annotations at `.github/workflows/ci.yml:451-454`, and the uncapped
`--report` in the step summary — all pre-existing, configured in `ci.yml:417-465`.
The natural <15 s discoverability probe (a col-5 prefix census) requires shell
operators preflight Check 10 rejects, and a full `ratchet` run exceeds its 15 s cap,
so no compliant inline `discoverability_test` exists without committing a wrapper
script — deliberately not added to keep the diff oracle-data-only.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "enumerate EVERY row the current report flags … all flagged rows, not just the issue's two" [brief] | Phase 1 + tables A/B | mapped |
| 2 | "decide delete-vs-add per the script's own remedies" [brief] | Disposition evidence + Phase 2 | mapped |
| 3 | "require re-running the ratchet to exit 0" [brief] | Phase 3 step 7 + AC-1 | mapped |
| 4 | "verify which remedy applies by reading the suite's actual reads" [brief] | Disposition evidence (components.test.ts read/exec grep; test_hook_emissions.sh:161) | mapped |
| 5 | "verify that path exists in ci.yml/ci-pr-affected-replay.py and how it behaves for an accept.tsv-only diff" [brief] | `oracle-inputs-changed` subsection | mapped |
| 6 | "do not duplicate its [PR #12103's] scope … do not comment on or edit that PR" [brief] | Sibling coordination (Overview) — verified KB-only file list | mapped |
| 7 | "re-pin the stale accept rows' anchor SHAs … or regenerate the accept file" [issue #12110] | — | descoped — justification: anchors are sha256 content prefixes, not git SHAs; stale rows are delete-only and no regenerate command exists (Cut list) |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| Delete 11 stale rows | "stale-accept … remedy: delete the accept row" (script remedy; ask 1) | asked |
| `glob:scripts/*sentry-issue.sh` edge member | "declare the path in AFFECTED_<LABEL>_PATHS … only when the suite really reads" (ask 2 — applied with the in-tree hot-anchor criterion; fork recorded) | inferred — justification: per-pair disposition fork, assumed default pending CTO ruling (decision-challenges.md) |
| 4 `tests/hooks/emissions` accept rows | "add an anchor-keyed accept row … only when the suite merely names the file" (asks 2, 4) | asked |
| Post-rebase re-verify step | "require re-running the ratchet to exit 0" (ask 3) + merged-tree learning | inferred — justification: anchor-keyed data goes stale on sibling merges; without the re-check the AC is unverifiable at merge time |

### Split Assessment

- Subsystems touched: 1 — `scripts/` (first-segment root)
- Planned files: 2 | Estimated changed lines: ~17 (11 deletes + 4 rows + 1 edge member + 1 comment)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` bodies searched for
`scripts/ci-pr-affected-audit.accept.tsv`, `scripts/lib/test-affected-paths.sh`,
`scripts/ci-pr-affected-replay.py`, `plugins/soleur/test/components.test.ts`: zero hits.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — CI oracle data repair on repo-internal
test-selection machinery. Mechanical UI-surface override: no `## Files to
Create`/`## Files to Edit` path matches the ui-surface term list → Product NONE.
Domain-leader fan-out unavailable in this subagent (no Task tool); recorded as
single-orchestrator assessment.

## Acceptance Criteria

- [ ] AC-1 `python3 -I scripts/ci-pr-affected-replay.py ratchet --report <file>` exits 0
  with `SOLEUR_PR_AFFECTED_RATCHET exit=0 reason=pass live=0 baseline=0` on the final
  branch tree, and re-passes after any rebase before arming.
- [ ] AC-2 Every one of the 11 stale-accept rows in table A is deleted from
  `scripts/ci-pr-affected-audit.accept.tsv`; no unflagged row is removed.
- [ ] AC-3 Each of the 3 new-pair findings in table B is drained by exactly one
  disposition per the script's remedies (edge declaration or accept rows covering
  every boundary line per `audit --all-refs`), with the chosen disposition's file
  changes landing in the same commit.
- [ ] AC-4 `awk -F'\t' 'NF==5 && $5 !~ /^false-positive: /'
  scripts/ci-pr-affected-audit.accept.tsv'` prints nothing (every new row's col-5
  reason carries the `false-positive:` + space prefix) — the one-malformed-row flood class.
- [ ] AC-5 The diff touches ONLY `scripts/ci-pr-affected-audit.accept.tsv` and (edge
  arm) `scripts/lib/test-affected-paths.sh` — no edits to the replay script, ci.yml,
  the baseline file, components.test.ts, or the two script files.
- [ ] AC-6 The PR's own `affected-index-ratchet` run prints the expected
  `oracle-inputs-changed:` warning naming the touched oracle file(s) and exits 0 —
  recorded in the PR body as the designed notice, not a defect.

## Test Scenarios

- Given the 11 stale rows and 3 live pairs, when the dispositions are applied, then
  `ratchet` exits 0 `reason=pass live=0 baseline=0` — `integration` (the ratchet IS
  the test harness; its own report is the assertion).
- Given a deliberately malformed col-5 reason on a new row, when
  `audit --accept` runs, then it exits 2 naming the row — proves AC-4's awk check is
  not vacuous (run once locally as a mutation probe, then revert). `integration`
- Given the edge arm is applied, when `ratchet` re-runs, then
  `plugins/soleur↔scripts/sentry-issue.sh` no longer appears in `new-pair` and no
  previously-covered pair becomes stale (`not-a-gap` on an existing accept row would
  mean the edge over-covers — check the stale list stays empty). `integration`
- Given main moved after the branch was cut, when the pre-arming re-run executes on the
  merged state, then `live=0` still holds or the fixpoint loop re-enumerates.
  `integration`

## Context

- Job is ADVISORY (`continue-on-error`, not in `scripts/required-checks.txt`) — the
  red is signal noise + merge-queue drag, not a hard block, but every PR shows it.
- `hr-write-boundary-sentinel-sweep-all-write-sites` — every flagged row enumerated in
  tables A/B; the enumeration is the complete current red set, superseding the issue's
  two-row list.
- Cold `ratchet` run measured at ~100+ s — run it with a generous timeout or in
  background (the 2026-10-26 learning hit a 120 s default timeout on a cold run).
- The issue body's "blocks: every queued PR" claim is now stale-severity: the job is
  advisory; the real cost is per-PR noise and ratchet-signal erosion. The fix still
  ships promptly because each day's drift can grow the flagged set.

## Alternative Approaches Considered

| Alternative | Why not chosen (default) |
|---|---|
| Re-pin stale anchors to newer content anchors (issue's recipe) | Impossible — anchors are sha256 line-content prefixes, not git SHAs; `not-a-gap` rows have no live line to re-pin to. |
| Regenerate accept.tsv wholesale | No such command; `--print-baseline` is prune-only and writes the baseline, not accept rows. |
| Uniform accept rows for all 3 pairs | Semantically purest per runbook, but `components.test.ts` is a 26-commits/90d file whose vendor block is designed to churn; the `plugins/soleur` suite's own convention post-PR5d is narrow globs for hot-anchor mention pairs. Recorded as the fork's alternative arm — if the parent rules this, Phase 2 step 4 names the exact rows. |
| Uniform narrow globs for all 3 pairs | Durable but declares edges on files the emissions suite provably never reads, against the suite's 10-row accept convention; recorded as the second alternative arm in step 5. |
| Declare `^scripts/sentry-issue.sh` exact-file edge for `plugins/soleur` | Exact-file edges of *named* files join the naming walk and can reveal new pairs; the sibling spellings all use the reveal-free `glob:` narrow form. |
| Defer stale-row repair to the pairs' authors | The flagged rows predate the current red state and span multiple merged PRs; the runbook's fallback owner (#10448) makes this repo-owned repair work, and every open PR pays the red meanwhile. |
