---
title: "fix: repair affected-index-ratchet red, top-15 suite-time report, apply-delivery re-queue (Ref #12001, #10033; epic #11556 Lever A2)"
type: fix
date: 2026-11-03
slug: ci-ratchet-suite-times-apply-redrive
branch: feat-one-shot-12001-10033-suite-times
issue: 12001
closes: [12001, 10033]
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix: repair affected-index-ratchet red, top-15 suite-time report, apply-delivery re-queue

## Enhancement Summary

**Deepened on:** 2026-11-03
**Sections enhanced:** 4 (Encryption Posture added; Observability, Guard Contract, Scope Check, Task-Design verified against deepen halt gates)
**Research agents used:** none — no Task/Agent tool on this harness; all gate checks executed inline and mechanically (`lint-guard-contract.py`, scope-check awk count, ratchet reproduction)

### Key Improvements

1. Verified the red state locally — `python3 -I scripts/ci-pr-affected-replay.py ratchet` reproduced `exit=1 reason=new-pair live=1518 baseline=1510` with the complete 8-line boundary set, so every accept-row anchor/ordinal in the disposition table is real, not transcribed from the issue.
2. Found the detection half of #10033 already shipped (#10879 `apply-delivery-gap-follower`), shrinking item 3 to the actuation arm; found GitHub's native `queue: max` (2026-05-07) and rejected it with mechanism-level reasoning (arriving-run-governs + storm backlog).
3. Added the `## Encryption Posture` declaration for the new `gh workflow run` write connection the redrive introduces.

### New Considerations Discovered

- `infra-privileged` environment verified live: `branch_policy` only, no reviewer gate — an automated `--ref main` dispatch runs unattended.
- PR #10928 touches `apply-deploy-pipeline-fix.yml` at `jobs:` ~651 and `track.sh` itself — the plan's zero-touch stance on that workflow also dodges a `track.sh` content collision beyond the accept-row question.
- `ci-pr-affected-replay-a` still measures 1348 s post-#11562-split on run 41693754894 — the top-15 report's leading outlier is pre-identified.

## Overview

One PR carrying three CI-time fixes from epic #11556's lever set. First, the advisory `affected-index-ratchet` job is red on every `merge_group` run since ~2026-11-02 (`exit=1 reason=new-pair`, live=1518 vs baseline=1510): eight undeclared suite-to-path pairs introduced by the key-rotate series (#11918, #11890, #11853, #11287) each need the ratchet's own remedy — a declared edge in `AFFECTED_<LABEL>_PATHS` where the suite really reads or executes the path (or the file's state feeds its verdict), or an anchor-keyed row in `scripts/ci-pr-affected-audit.accept.tsv` where it merely names it — followed by the shrink-only baseline regeneration. This un-pauses the #10865 soak that gates the #10448 go/no-go. Second, Lever A item 2 gets its measurement deliverable: a committed top-15 suite-time report derived from the `suite-timings-*` CI artifacts, naming the outliers by cause class (sleep-waits, lock contention, repeated tool installs) so the next Lever-A slice is pre-staged ahead of the first `wallclock-p90-watch` report (#11954). Third, `apply-deploy-pipeline-fix.yml` push runs are silently cancelled by pending-slot eviction in the shared `terraform-apply-web-platform-host` concurrency group during merge-queue drains (#10033): the detection half already ships in `apply-delivery-gap-follower.yml`/`scripts/apply-delivery-gap.sh` (#10879), so the fix closes the loop — a bounded, class-gated re-dispatch job makes evicted deliveries re-queue while apply serialization is preserved exactly.

## Research Insights

**Premise Validation (Phase 0.6).** All six cited issues are OPEN (#12001, #11556, #10033, #10865, #10448, #11954); the four key-rotate PRs are MERGED; the five flagged sibling PRs are OPEN and touch the named files. Every file the feature description cites exists on `origin/main` (verified via `git cat-file -e`). **One stale premise found:** #10033 proposes "(a) post-merge verification step that asserts a concluded apply run exists per trigger merge and re-dispatches on `cancelled`" — that detection half **already shipped** as `apply-delivery-gap-follower.yml` + `scripts/apply-delivery-gap.sh` (#10879, which cites #10033 in its header). What remains is actuation: the follower files a deduplicated `apply-delivery-gap` issue with printed `gh workflow run` commands a human must execute; nothing re-queues automatically. Collision precheck: PR #12002 names #12001 and #10033 — it is this pipeline's own auto-created draft on this branch, not a foreign duplicate; four `test-all.sh` processes in sibling worktrees are unrelated runs. **New external fact:** GitHub shipped a native `queue: max` concurrency property (changelog 2026-05-07; `docs.github.com/en/actions/.../control-workflow-concurrency`) allowing up to 100 pending runs per group — evaluated and rejected below (Alternatives).

**Property List (Phase 0.6b).**

1. `affected-index-ratchet` exits 0 on `merge_group` and `pull_request` runs on a tree carrying this diff (live gap set == committed baseline again); the eight pairs are dispositioned per the ratchet's own doctrine and the audit is re-run to a fixpoint under DRAIN-REVEAL.
2. A committed top-15 suite-time report exists, derived from real `suite-timings-*` artifacts, naming each outlier's cause class with evidence — the next Lever-A slice is pre-staged ahead of #11954's Friday report.
3. A trigger-file merge's delivery can no longer be silently lost to pending-slot eviction: pending deliveries survive or re-queue, apply serialization (one `terraform apply` at a time against the lockless R2 backend) is preserved exactly, and the re-queue path is detectable and bounded.

**Cut List (Phase 0.6b).**

- New report-generation tooling for item 2 — property 2 is a document; the Oct-29 brainstorm's CTO already ruled `sort -t$'\t' -k2 -rn` covers the need ad hoc ("nice to have, not tooling to build"); `scripts/watch-shard-balance-11564.sh` already implements the artifact-download pattern for citation. The report embeds the exact commands for reproducibility instead.
- A new watcher/workflow for item 3 — `apply-delivery-gap-follower.yml` already senses and adjudicates the exact state (pending-eviction → `evicted-before-start` row); only its actuation arm is missing.
- Any change to `apply-deploy-pipeline-fix.yml` itself — the issue's options (b)/(c) are infeasible (see Alternatives), and open PR #10928 already edits that file at `jobs:` ~line 651; zero-touch avoids the collision entirely.

**Relevant file paths.**

- `scripts/lib/test-affected-paths.sh:951` — `AFFECTED_PLUGINS_SOLEUR_PATHS` (already declares `scripts/inngest-key-rotate.sh` :1004, `scripts/key-rotate.sh` :1005); label-map comment at :349-356 defines the `AFFECTED_<LABEL>_PATHS` grammar.
- `scripts/ci-pr-affected-audit.accept.tsv` — 455 rows; schema `suite<TAB>path<TAB>anchor<TAB>ordinal<TAB>false-positive: <reason>` (`scripts/ci-pr-affected-replay.py:122-129`).
- `scripts/ci-pr-affected-replay.py` — audit/ratchet authority: accept schema :122, RATCHET semantics :135, DRAIN-REVEAL fixpoint rule :98-101, `--print-baseline` shrink-only semantics :157.
- `scripts/inngest-key-rotate.sh` — :133 `KR_TRACK` default, :134 `KR_HOST_STATE` default, :271 `source bearer-curl.sh` inside `kr_init`, :339 `bash "$KR_HOST_STATE"`, :384 conditional `source betterstack-read-classify.sh`, :1126 `bash "$KR_TRACK"`; test seams :42/:56.
- `scripts/key-rotate.sh:566` — `env -i ... bash ".../test-tf-redact-random-ids.sh"` inside `kk_cmd_precondition`.
- `apps/web-platform/infra/run-registered-suites.sh:756` — `"apps/web-platform/infra/key-rotate-workflow.test.sh=840"` inside `_SUITE_BOUNDS` → `SOLEUR_SUITE_TIMEOUTS`.
- `plugins/soleur/test/terraform-target-parity.test.ts:9884-9968` — Guard 5 `krTables()` SOURCES both scripts for `KR_GATE_TABLE`/`KK_COPIES`; :3456-3480 asserts workflow run-steps contain `dispatch-web-redeploy/track.sh` (PL1).
- `plugins/soleur/test/sole-copy-drift-check.test.sh:79` — `LIBREAL=scripts/lib/bearer-curl.sh`, copied (`:724`) and `cmp -s` drift-asserted (`:1533`); `plugins/soleur/test/heartbeat-reconcile-issue-step.test.sh:800` greps its refusal string.
- `scripts/followthroughs/jobs1-stopgap-7432.test.sh:393` — `grep -vE '^[ ]*#' "$RUNNER"` then asserts five literals (none is the bounds entry).
- `scripts/test-all-killed-classification.test.sh:173` — drives the real runner over `SOLEUR_INFRA_DIR` fixture dirs (registration replaced → bounds entry never engages).
- `scripts/lib/test-suite-lanes.test.sh:30-46` — censuses `SUITE_COMMAND` records and lane-token resolvability (bounds entry is not a verdict input).
- `.github/workflows/apply-delivery-gap-follower.yml` — `workflow_run` on both apply workflows, `permissions: contents/actions:read, issues:write`; header says "DETECTION ONLY".
- `scripts/apply-delivery-gap.sh` — `WATCHED` table :75-78 (`deploy-fix|...|150` cap, `infra|...|120`); `class_for_total` :98 (`evicted-before-start` vs `cancelled-mid-run`); `render_body` :564-618 prints the manual `gh workflow run` commands; `N_INFLIGHT` deferral :536-547; aged-60min escalation :610.
- `.github/workflows/apply-deploy-pipeline-fix.yml` — shared group block :183-202 (LOAD-BEARING comment); `apply` job `environment: infra-privileged` :242; `workflow_dispatch` requires `reason`, optional `allow_missing_status_endpoint` (default false).
- `apps/web-platform/infra/infra-privileged-environment.tf:56` — `infra-privileged` protection = `branch_policy` only (verified live via `gh api …/environments/infra-privileged`: `protection_rules: ["branch_policy"]`, `can_admins_bypass: true`) — an automated `--ref main` dispatch runs unattended.
- `plugins/soleur/test/apply-delivery-gap-follower.test.sh` — 1507-line mutation suite; asserts the workflow's parsed shape AND raw text, and the script's emit contract; synthetic fixtures via `--fixture-dir`.
- `scripts/watch-shard-balance-11564.sh:81-104` — the artifact-download pattern to cite: `gh run download $rid -R $GH_REPO -p 'suite-timings-scripts-*' -D "$d"`, `ARTIFACT_NAME_RE='^suite-timings-(scripts|scripts-heavy)-[0-9]+$'`.
- `scripts/suite-durations.tsv` (committed prices, `floor` rows = never-measured), `scripts/suite-shard-legs.tsv` (ADR-240 manifest), `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md` (cohort method).
- `.github/workflows/wallclock-p90-watch.yml` — Lever E1 sibling watch (#11774); its first scheduled run is #11954's Friday target.
- `knowledge-base/engineering/audits/` — convention for dated committed analyses (`2026-10-14-github-code-quality-baseline.md`, `2026-07-20-cron-liveness-cohort-audit.md`).

**Institutional learnings applied.**

- `2026-10-30-audit-accept-rows-need-every-boundary-line-…` — accept rows must cover EVERY boundary line; the authority is `python3 -I scripts/ci-pr-affected-replay.py audit --all-refs`, not the ratchet report's per-pair ref display. (Verified locally: the complete boundary set for this red is exactly 8 ref lines — anchors below.)
- `2026-11-03-verdict-input-edges-and-the-442-pair-myth` — the declare-vs-accept criterion is "reads or executes, **or whose state feeds the suite's verdict**" (PR #11955 widened all four statement sites); `.gitignore`-class non-code files can't enter the naming walk.
- `2026-10-29-decompose-ci-leg-wallclock-from-suite-timings-before-attributing-overhead` — `gh run download <run> -n suite-timings-scripts-N` needs `-R owner/repo`; artifacts live ~14 days; exclude `__run_boundary_*` sentinel rows; PR-event medians ≠ merge_group medians.
- `registry-host-replace-dispatch.yml:67-95` — the same pending-eviction class solved intra-workflow by last-successful-run watermark subsumption ("eviction coalesces deliveries"); inapplicable cross-workflow (an `apply-web-platform-infra` successor's `-target` set does not cover `deploy_pipeline_fix`).
- `2026-09-14-a-systemd-state-…` — #8135's host delivery was cancelled twice by this same group; the class predates the follower.
- `merge-queue-ejections-…-20261005` — decompose aggregate failure by run before choosing a fix; here the decomposition is already in the follower (`evicted-before-start` vs `cancelled-mid-run`).

**Related issues/PRs.** #12001 (this red), #10865 (paused soak — "repair main first"), #10448 (go/no-go gate), #10859 (durable fix: required-context promotion, budget-held — NOT in scope), #11694/#11796/#11848/#11897 (four prior recurrences), #11556 (epic), #11562 (CLOSED — atomic-suite split already landed; `ci-pr-affected-replay-a` still measures 1348 s on run 41693754894), #11954, #10033, #9938 (measurement PR), #10879 (follower), #11329 (first filed+closed gap issue), #4844 (shared-group origin). Open sibling diffs on our files: #11958 (accept+baseline+test-affected-paths), #11950 (accept+baseline), #11949 (accept), #11994 (test-affected-paths), #10926 (test-affected-paths), #10928 (both apply workflows + `track.sh`).

**External research.** GitHub docs + 2026-05-07 changelog: `concurrency.queue` — `single` (default; arriving run cancels existing pending and takes its place) vs `max` (≤100 pending, FIFO sequential; invalid with `cancel-in-progress: true`). The eviction action is performed by the *arriving* run per its own declaration — a `queue: max` declaration protects only that run's own arrivals, so rescuing `apply-deploy-pipeline-fix` runs from `apply-web-platform-infra` arrivals requires `queue: max` on **every** member of `terraform-apply-web-platform-host` (≥6 declaration sites: two workflow-level + `cf-lb-overlay`, `inngest-provision-rehearsal`, job-level in `inngest-key-rotate.yml` ×2, conditional-expression in `key-rotate.yml`).

## Research Reconciliation — Spec vs. Codebase

| Spec/brief claim | Reality on main | Plan response |
|---|---|---|
| #10033: fix needs "post-merge verification step … re-dispatches on `cancelled`" | Detection+issue already shipped (#10879); `scripts/apply-delivery-gap.sh:578-580` already prints the exact dispatch commands — to a human | Build only the actuation arm (redrive job) on the existing follower; keep its sense/adjudicate step untouched |
| #12001: "8 new-pairs" | Verified locally — `ratchet` reproduces `exit=1 reason=new-pair live=1518 baseline=1510` with exactly 8 `ref` boundary lines (report captured) | Disposition table below is pre-staged from real boundary lines + suite-read evidence, not guessed |
| Epic Lever A item 1: "shard assignment should be derived from suite-timings" | Already shipped (ADR-240, `regenerate-shard-manifest.py`, `suite-shard-legs.tsv`); Lever A2's report is the unscheduled remainder | Report-only deliverable; no manifest machinery |
| Suite timings are "already uploaded" | Confirmed: 11 `suite-timings-*` artifacts live on run 41693754894, format `label<TAB>ms<TAB>tmp_delta=N` + `__run_boundary_*` sentinels | Report method = last 5 green `merge_group` ci.yml runs, median per label |

## Problem Statement / Motivation

Three independent red/silent-loss states, all inside the epic's CI-time blast radius:

1. **#12001** — the advisory ratchet is silently red on `merge_group` (advisory, so runs stay green while the soak probe pauses on the red). Each recurrence is fixed by hand; this is the fifth. The eight pairs and their remedies are enumerated by the job itself; the work is a correct declare-vs-accept judgment per pair plus the fixpoint and baseline regen.
2. **Epic #11556 Lever A2** — the top-15 suite-time report is the pre-staging input for the next Lever-A slice; `wallclock-p90-watch` (#11954) starts reporting Friday and this report names *which* suites the p90 is made of and *why* (sleep-waits, lock contention, repeated installs).
3. **#10033** — a concurrency group holds 1 running + 1 pending; a third arrival cancels the pending run even with `cancel-in-progress: false`. Trigger-file merges lose delivery with no signal. The follower now *sees* the loss and files an issue, but remediation is a human reading the issue and pasting `gh workflow run` — during a storm that human is the queue.

## Proposed Solution

### Phase 1 — Ratchet repair (#12001)

Run `python3 -I scripts/ci-pr-affected-replay.py audit --all-refs` to confirm the boundary set, then apply the pre-staged dispositions (each verified against the doctrine "the suite really reads or executes the file, or the file's state feeds its verdict" — verified evidence below; if `audit --all-refs` contradicts a row, the doctrine governs, not this table):

| Suite | Path | Citing boundary line | Anchor/ord | Disposition | Evidence |
|---|---|---|---|---|---|
| `plugins/soleur` | `.github/actions/dispatch-web-redeploy/track.sh` | `scripts/inngest-key-rotate.sh:133` (`KR_TRACK=` default) | `5452d84ed3f7/1` | **declare** in `AFFECTED_PLUGINS_SOLEUR_PATHS` | Verdict input: `terraform-target-parity.test.ts:3456-3480` asserts workflow run-steps *contain* `dispatch-web-redeploy/track.sh` — a rename reds the suite; the file's name-state feeds the verdict |
| `plugins/soleur` | `scripts/inngest-host-state.sh` | `scripts/inngest-key-rotate.sh:134` (`KR_HOST_STATE=` default) | `ee3c60cbf52f/1` | accept row | Name-mention: a test-seam default path; the suite sources the script for `KR_GATE_TABLE` only; nothing reads the file and no assertion pins its name |
| `plugins/soleur` | `scripts/lib/bearer-curl.sh` | `scripts/inngest-key-rotate.sh:271` (`source`) | `e60a4b0a797d/1` | **declare** | Real read: `sole-copy-drift-check.test.sh` copies (`:724`) and `cmp -s`-asserts (`:1533`) the committed file |
| `plugins/soleur` | `scripts/lib/betterstack-read-classify.sh` | `scripts/inngest-key-rotate.sh:384` (`local lib=` conditional source) | `e4c924e0cdf5/1` | accept row | Name-mention: conditional runtime source inside `kr_bs_classify`, a function the suite never invokes |
| `plugins/soleur` | `tests/scripts/test-tf-redact-random-ids.sh` | `scripts/key-rotate.sh:566` (`env -i … bash` exec) | `f5e7e4e1063c/1` | accept row | Name-mention: runtime-only execution inside `kk_cmd_precondition`, never invoked by `krTables()` |
| `scripts/jobs1-stopgap-7432` | `apps/web-platform/infra/key-rotate-workflow.test.sh` | `run-registered-suites.sh:756` (`_SUITE_BOUNDS` entry) | `890796c7268b/1` | accept row | Name-mention: the suite greps the runner for five literals (`jobs1-stopgap-7432.test.sh:393-398`); the bounds entry is not one of them |
| `scripts/lib/test-suite-lanes.test.sh` | same | same | `890796c7268b/1` | accept row | Name-mention: the suite censuses `SUITE_COMMAND` records + lane tokens; the bounds entry feeds neither |
| `scripts/test-all-killed-classification` | same | same | `890796c7268b/1` | accept row | Name-mention: the suite drives the runner over `SOLEUR_INFRA_DIR` fixture dirs; the registered bound never engages |

Then: **DRAIN-REVEAL fixpoint** — declaring `bearer-curl.sh` and `track.sh` makes the audit *read* them (both are CODE_EXT-admitted), which can reveal further pairs; re-run `ratchet` and disposition any new rows the same way. Finally regenerate the baseline: `python3 -I scripts/ci-pr-affected-replay.py ratchet --print-baseline > scripts/ci-pr-affected-audit.baseline.tsv` (shrink-only, C-locale, final newline; refuses on a degraded census — fail-closed). Rows are **additive only**: append to `AFFECTED_PLUGINS_SOLEUR_PATHS` and to `accept.tsv`; do not restructure — open PRs #11958/#11950/#11949/#11994/#10926 touch the same files. Baseline regen will conflict with #11958/#11950 drains — resolve by re-running `--print-baseline` after the next Phase-7-style sync rather than hand-merging the file.

### Phase 2 — Top-15 suite-time report (epic Lever A2)

Committed analysis artifact at `knowledge-base/engineering/audits/2026-11-0X-suite-time-top-15-report.md` (dated to authoring day). Method (embedded verbatim in the report's Methods section):

1. Enumerate the last 5 green `merge_group` `ci.yml` runs (`gh run list --workflow ci.yml --branch main --event merge_group --status success -L 5 --json databaseId`); merge_group is the canonical full-matrix run (`watch-shard-balance-11564.sh:18-21` — push runs routinely carry no artifacts, and PR-event medians are a different distribution).
2. `gh run download <rid> -R jikig-ai/soleur -p 'suite-timings-scripts-*' -D <dir>` per run (artifacts live 14 days; also `-p 'suite-timings-infra-*'` for completeness if present — `scripts` and `scripts-heavy` families only are required).
3. Concatenate all `*/suite-timings.tsv`, drop `__run_boundary_*` sentinels, median per label across the 5-run sample, rank desc → top 15.
4. For each top-15 label: committed price from `suite-durations.tsv` (flag `floor` rows — never-measured is itself a finding per the Oct-29 learning), leg from `suite-shard-legs.tsv`, and cause class from a targeted evidence grep of the suite file: `sleep [0-9]` / `KR_SLEEP`-style seams → sleep-waits; `flock|/lock|mutex|serial` → lock contention; `bun install|npm ci|curl -.*-o |apt-get install|playwright install|pip install` → repeated tool installs; fixture-rebuild loops (`for .* in .*; do … env -i`) → per-row spawn cost.
5. Report sections: ranked table (label, median ms, leg, priced-vs-measured delta, cause class, evidence pointer), the outliers named with remedy sketch (split `--rows` precedent / bound / rewrite), and a "pre-staged next slice" paragraph naming the 2-3 actionable issues to file at work time — filed as real issues during implementation per the deferral-tracking rule.

### Phase 3 — Apply-delivery re-queue (#10033)

Extend the shipped follower with a bounded actuation arm, ADR-189-shaped (sense/adjudicate/actuate stay separate):

- `scripts/apply-delivery-gap.sh`: after `reconcile_issue`, emit a machine-readable eligibility output — e.g. append `redrive_deploy_fix=true|false` (and symmetric `redrive_infra=false` reserved, always false this slice) to `$GITHUB_OUTPUT` when present — `true` only when `N_ROWS > 0` AND every `deploy-fix` row's `class` is `evicted-before-start` (zero jobs ran → nothing partial; `cancelled-mid-run` stays human-only per the script's own `:587` warning) AND `N_INFLIGHT == 0` for `deploy-fix` (a live run defers; the completion re-fires the follower anyway).
- `.github/workflows/apply-delivery-gap-follower.yml`: new job `redrive` — `needs: follow`, `if: needs.follow.outputs.redrive_deploy_fix == 'true'`, job-level `permissions: actions: write` ONLY (the `follow` job keeps `actions: read` — the write grant is scoped to the actuation), runs `gh workflow run apply-deploy-pipeline-fix.yml --ref main -f reason="apply-delivery-gap redrive ${{ needs.follow.outputs.short_sha }}"`. Header updated: no longer "DETECTION ONLY" — document the bounded actuation, its class gate, and why it cannot widen (no dispatch input for `allow_missing_status_endpoint`, deploy-fix scope only, one dispatch per reconcile; the dispatched run lands in the same `terraform-apply-web-platform-host` group so serialization is untouched — if evicted again, the next completed run re-fires the follower and re-dispatches; convergence is bounded by storm-end and the existing 60-minute aged-issue escalation).
- `plugins/soleur/test/apply-delivery-gap-follower.test.sh`: additive rows — fixture asserting `redrive_deploy_fix=true` on an eligible gap, `false` on `cancelled-mid-run`, `false` when a non-stale in-flight run exists, `false` when delivered; workflow-shape assertions for the `redrive` job's `needs`/`if`/permission scope and the `follow`-job output wiring.
- `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-red-run.md`: document the redrive arm and the residual (a sustained storm can re-evict redispatched runs; the aged issue is the floor).
- New ADR (provisional ordinal **ADR-318**, verify free at work — sibling PRs claim ordinals in-flight): "the apply-delivery-gap follower may actuate a bounded re-dispatch of the workflow that lost a pending run" — the merge-as-authorization model is unchanged (redrive completes an already-authorized delivery, never originates one; `cancelled-mid-run` stays human).

## Files to Edit

- `scripts/lib/test-affected-paths.sh` — add `scripts/lib/bearer-curl.sh` and `.github/actions/dispatch-web-redeploy/track.sh` to `AFFECTED_PLUGINS_SOLEUR_PATHS` (with per-line `why` comments matching house style).
- `scripts/ci-pr-affected-audit.accept.tsv` — append 6 anchor-keyed rows per the disposition table (reason names the line kind per the remedy contract).
- `scripts/ci-pr-affected-audit.baseline.tsv` — regenerated via `--print-baseline` (shrink-only).
- `scripts/apply-delivery-gap.sh` — emit `redrive_deploy_fix` output + self-test coverage of the eligibility predicate.
- `.github/workflows/apply-delivery-gap-follower.yml` — wire `follow` step `id:` + `outputs:`, add `redrive` job, update header contract.
- `plugins/soleur/test/apply-delivery-gap-follower.test.sh` — additive fixture + shape rows.
- `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-red-run.md` — redrive section.
- `knowledge-base/engineering/architecture/decisions/ADR-317-*.md` region — new ADR file (provisional 318).

## Files to Create

- `knowledge-base/engineering/audits/2026-11-0X-suite-time-top-15-report.md` — the Lever A2 report.
- `knowledge-base/engineering/architecture/decisions/ADR-318-apply-delivery-gap-follower-may-redrive.md` (provisional ordinal).
- `knowledge-base/project/specs/feat-one-shot-12001-10033-suite-times/{spec.md,tasks.md,decision-challenges.md}` — pipeline artifacts.

## Open Code-Review Overlap

Checked 2026-11-03 against open `code-review`-labeled issues — **None** touch the planned files (the check ran; sibling functional PRs above are tracked separately).

## Technical Considerations

- **Additive-only discipline on shared files.** `test-affected-paths.sh`, `accept.tsv`, `baseline.tsv` are under active drain by ≥5 open PRs. Append-only edits; regenerate, never hand-merge, the baseline.
- **ADR-189 boundary.** The `follow` job stays sense+adjudicate with `actions: read`; the `redrive` job alone carries `actions: write`. The verification surface still never writes — it emits a boolean the actuation job consumes.
- **Authorization model.** The push merge is the human authorization (workflow header). A redrive dispatch applies `main` HEAD — the same content the printed manual command applies; it cannot apply anything the merge did not authorize, and `cancelled-mid-run` rows (possibly-partial state) are excluded by design.
- **Mixed `queue:` declarations.** `queue:` governs the *arriving* run's behavior, not the pending run's defense — confirmed by doc semantics; flagged as a verification note for any future `queue: max` adoption.
- **No new autonomous-task file.** Phase 2.9.3 Task Design does not fire (existing workflow, new job inside it); the redrive's dedupe/human-reentry/self-disable properties are documented inline in the Observability section instead.
- **NFR register:** CI wall-clock (epic #11556 DoD surface) and prod-delivery correctness are the touched non-functional properties; no latency/cost regression introduced — the redrive fires only on real gaps.
- **CLI-verification:** `gh workflow run <wf> --ref main -f reason=<s>` matches the exact command shape `apply-delivery-gap.sh:580` already prints for humans; `gh run download -p <glob> -D <dir>` matches `watch-shard-balance-11564.sh:85`; `gh run list --workflow … --event merge_group` verified in-session for the artifact query.

## User-Brand Impact

- **If this lands broken, the user experiences:** the required `test`/`merge_group` battery and the plugin's CI templates our users copy — a wrongly-accepted pair becomes an affected-selection escape that ships a regression a user's repo would have caught, and a misbuilt redrive applies host-config files to the production web host silently.
- **If this leaks, the user's [workflow] is exposed via:** the S4 affected-selector consuming a false-negative accept row (a needed suite silently not selected), or a redrive that acts without the merge-authorization the model assumes.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** same surface the Oct-12 path-aware-gating brainstorm rated `single-user incident` (a silent selection escape ships a user-facing regression); the redrive touches the prod-delivery channel whose authorization model is reviewed-merge only. CPO sign-off required at plan time before `soleur:work`; `soleur:engineering:review:user-impact-reviewer` fires at review time. (Headless note: no Task tool on this harness — the CPO consult is recorded as a pending row in `decision-challenges.md`.)

## Observability

```yaml
liveness_signal:
  what: "apply-delivery-gap follower reconcile summary (`::notice::apply_delivery_gap_summary mode=… rows=… issue=…`) plus its one deduplicated `apply-delivery-gap` tracker issue"
  cadence: "per completed run of either apply workflow (workflow_run)"
  alert_target: "GitHub issue tracker (`apply-delivery-gap` label; action-required + priority/p1-high; p0 when cancelled-mid-run present)"
  configured_in: ".github/workflows/apply-delivery-gap-follower.yml + scripts/apply-delivery-gap.sh"
error_reporting:
  destination: "the same tracker issue family (`infra: apply delivery gap follower degraded` on read/write failure)"
  fail_loud: "follower exits non-zero on a failed reconcile (red run visible in Actions); redrive job failure surfaces as a red run on the same workflow"
failure_modes:
  - mode: "redispatched run evicted again during a sustained storm"
    detection: "next reconcile still lists the push undelivered; issue stays open and ages (60-min aged-marker escalation)"
    alert_route: "the standing gap issue (priority/p1-high, p0 on mid-run rows)"
  - mode: "redrive dispatched while a cancelled-mid-run row exists for deploy-fix"
    detection: "eligibility predicate returns false — the suite asserts the negative case"
    alert_route: "n/a (control fails closed)"
  - mode: "ratchet repair missed a boundary line (accept under-cover)"
    detection: "`ratchet` stays exit=1 new-pair on the PR's own run"
    alert_route: "PR required checks / the advisory job's ::error annotation"
logs:
  where: "GitHub Actions run logs for Apply Delivery Gap Follower + each dispatched apply run; the gap issue body rewrites each reconcile"
  retention: "run logs ~90 days; artifacts 14 days; issue history durable"
discoverability_test:
  command: "bash scripts/apply-delivery-gap.sh --self-test"
  expected_output: "apply_delivery_gap_self_test=ok"
```

## Encryption Posture

```yaml
in_transit:
  - connection: "apply-delivery-gap-follower `redrive` job (github-hosted runner) -> api.github.com `gh workflow run` dispatch"
    enforced_at: "scripts/apply-delivery-gap.sh redrive output + the redrive job's `run:` step (new)"
    tls: "https, TLS 1.2+ (gh CLI default transport)"
    cert_verification: on
    does_not_defend: "token-scope misuse — mitigated by scoping `actions: write` to the redrive job only and gating the dispatch on the class predicate; a forged eligible state requires write access to the repo's own workflow state"
    disclosed_as: not-publicly-claimed
```

No `at_rest` rows: the plan introduces no persistent store — the concurrency "queue" tokens are GitHub Actions run-queue semantics, not a data store. `exception` omitted: `cert_verification` is `on` and no mechanism is `plaintext-exception`.

## Guard Contract

### Guard 1 — Redrive eligibility predicate

**Property.** A `redrive` dispatch fires only for a `deploy-fix` gap whose every row is `evicted-before-start` with no non-stale in-flight run — never for `cancelled-mid-run`, never while a live run already covers delivery, and at most once per reconcile.

**Assembly.** The predicate inside `scripts/apply-delivery-gap.sh` computes over `$ROWS` (written by `reconcile_workflow`) and `N_INFLIGHT` (written by `count_inflight`); the workflow consumes exactly one output name (`redrive_deploy_fix`) in `redrive.if`; the dispatch command is one `gh workflow run` line. Chokepoints: the single `$GITHUB_OUTPUT` write site in the script and the single `if:` expression in the workflow — both named here, so an added second dispatch site or a second output name is a contract violation.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Fixture: cancelled run, zero jobs, no later success → row `evicted-before-start` | `redrive_deploy_fix=true` emitted (must-PASS arm proves the guard isn't reject-everything) |
| 2 | Fixture: cancelled run with ≥1 job (`total_count>0`) → row `cancelled-mid-run` | `redrive_deploy_fix=false` — the dispatch precondition holds and the property still fails |
| 3 | Fixture: eligible gap plus a non-stale `in_progress` run at a descendant SHA | `redrive_deploy_fix=false` — second-member-after-compliant-first case |
| 4 | Workflow text: `redrive` job's `if:` loses the `== 'true'` comparison or gains a second `gh workflow run` line | suite shape assertion RED — the dispatch chokepoint is singular |
| 5 | Suite harness: remove the `gh` spy's `workflow run` entry so a dispatched call is unrecorded | at least one assertion RED — a vacuous harness cannot pass |

## Architecture Decision (ADR/C4)

### ADR

New ADR, **provisional ordinal 318** (verify next-free at work; renumber sweeps `grep -rn 'ADR-318' knowledge-base/project/{plans,specs}/feat-one-shot-12001-10033-suite-times/`): *the apply-delivery-gap follower may actuate a bounded re-dispatch* — sense/adjudicate/actuate split preserved at job+permission granularity (ADR-189 shape); merge-as-authorization unchanged; `cancelled-mid-run` excluded; one dispatch per reconcile; infra redrive explicitly deferred.

### C4 views

No C4 impact. Enumeration checked against `model.c4`/`views.c4`/`spec.c4`: (a) external human actors — none (the redrive actor is the workflow itself, already inside the repo's CI boundary); (b) external systems/vendors — GitHub Actions and the Hetzner/CF hosts are already modeled (`github` system, tunnel/web elements); the redrive adds no new edge — the `apply-deploy-pipeline-fix` apply path already exists; (c) containers/data stores — R2 state and the web hosts are already modeled; (d) access relationships — the `actions: write` grant is a workflow-internal permission, not a model edge. CI-workflow internals are not C4 elements in this repo's model conventions.

### Sequencing

The ADR is authored `status: adopting` in this PR — the redrive arm's post-merge behavior is itself the observation (first auto-redispatch recorded in a follow-up comment on #10033).

## Domain Review

**Domains relevant:** Engineering, Operations

### Engineering

**Status:** reviewed
**Assessment:** Internal CI/infra tooling only. Assessment-only (no leader spawn — no Task tool on this harness): the declare/accept doctrine, DRAIN-REVEAL fixpoint, and ADR-189 job-boundary shape are established repo conventions cited inline; `queue: max` rejected on arriving-governs semantics + storm backlog math.

### Operations

**Status:** reviewed
**Assessment:** Assessment-only: the redrive actuates the same `infra-privileged` environment the push path already uses (`branch_policy` only — verified `gh api …/environments/infra-privileged`); no new credentials, vendors, or spend. Runner cost of a redrive = one apply run on a real gap only.

### Product/UX Gate

Product domain not relevant — no `components/**/*.tsx`, `app/**/page.tsx`, or other UI-surface paths in Files to Create/Edit; the mechanical UI-surface override does not fire.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "real reads/executions → declare in AFFECTED_<LABEL>_PATHS in scripts/lib/test-affected-paths.sh; mere name-mentions → anchor-keyed accept rows in scripts/ci-pr-affected-audit.accept.tsv" [brief] | Phase 1 / disposition table / Files-to-Edit rows 1-3 | mapped |
| 2 | "produce a top-15 suite-time report from the uploaded `suite-timings-*` CI artifacts — name the outliers (sleep-waits, lock contention, repeated tool installs) … Deliverable: a committed analysis artifact" [brief] | Phase 2 / audits file | mapped |
| 3 | "The fix must preserve apply serialization (no parallel terraform applies) while making pending deliveries survive or re-queue." [brief] | Phase 3 / follower redrive | mapped |
| 4 | "Additive rows only; do not restructure those files." [brief] | Files-to-Edit constraint notes | mapped |
| 5 | "open PR #10928 touches the same workflow file for unrelated webhook work — additive changes only" [brief] | Cut List (zero-touch on apply-deploy-pipeline-fix.yml) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| Ratchet disposition table + fixpoint + baseline regen | "Remedy per the job's own output: real reads/executions → declare in AFFECTED_<LABEL>_PATHS" [brief] | asked |
| `audits/` top-15 report | "Deliverable: a committed analysis artifact (choose location per repo convention, likely knowledge-base/engineering/)" [brief] | asked |
| Follower redrive job | "making pending deliveries survive or re-queue" [brief] | asked |
| ADR-318 + test/runbook edits | — | inferred — the follower gains a write actuation, a recorded-architecture divergence (`wg-architecture-decision-is-a-plan-deliverable`), and the workflow-shape test suite asserts this file's contract so it must move with it |
| `decision-challenges.md` rows | — | inferred — headless pipeline persistence channel for the pending technical rulings |

### Split Assessment

- Subsystems touched: 4 — `scripts/`, `.github/`, `plugins/soleur/`, `knowledge-base/`
- Planned files: 10 | Estimated changed lines: ~420
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines → root count trips (4)
- Recommendation: single PR — the brief mandates "Fix three CI-time items in ONE PR"; the threshold trip is noted and accepted verbatim rather than splitting against the ask.

## Acceptance Criteria

- [ ] AC1. `python3 -I scripts/ci-pr-affected-replay.py ratchet` on the PR tree prints `SOLEUR_PR_AFFECTED_RATCHET exit=0` — every one of the 8 pairs is declared or accepted, zero `stale`/`unaudited`/`new-pair`/`baseline-*` rows, and the DRAIN-REVEAL fixpoint converged (declaring `bearer-curl.sh`/`track.sh` minted no unhandled residue).
- [ ] AC2. `scripts/ci-pr-affected-audit.accept.tsv` gained exactly the planned anchor-keyed rows (or the audit-driven correction set), each `anchor`/`ordinal` matching a `ref` line of `audit --all-refs`; `baseline.tsv` is `--print-baseline` output, C-locale sorted with a final newline.
- [ ] AC3. The `affected-index-ratchet` job's own step on this PR's `pull_request` run prints `exit=0` (advisory-green arm proven in-run, not asserted in prose).
- [ ] AC4. `knowledge-base/engineering/audits/2026-11-0X-suite-time-top-15-report.md` names the top-15 suite labels by median ms over ≥4 green `merge_group` runs, each with leg, committed-price delta (`floor` rows flagged), cause class, and a repo-path evidence pointer; its Methods section reproduces the analysis from commands alone.
- [ ] AC5. `apply-delivery-gap-follower.yml` gains a `redrive` job that dispatches `gh workflow run apply-deploy-pipeline-fix.yml --ref main -f reason=…` only when `needs.follow.outputs.redrive_deploy_fix == 'true'`; `actions: write` appears on that job only and `follow` keeps `actions: read`.
- [ ] AC6. `scripts/apply-delivery-gap.sh` emits `redrive_deploy_fix=true` iff `deploy-fix` rows exist AND all are `evicted-before-start` AND `N_INFLIGHT == 0`; the predicate's true and three false shapes are each asserted in `apply-delivery-gap-follower.test.sh` and the suite passes.
- [ ] AC7. `terraform-apply-web-platform-host` group text is byte-identical in `apply-deploy-pipeline-fix.yml` and `apply-web-platform-infra.yml` — apply serialization unchanged (`diff` of the two concurrency blocks on the group literal).
- [ ] AC8. ADR-318 (or the next-free ordinal) exists with the adopt/amend content above and `status: adopting`; the C4 no-impact enumeration is written into its body or the plan's.
- [ ] AC9. Deferral issues are filed at work time for: `queue: max` re-evaluation (with arriving-governs verification), `infra`-key redrive extension, and each actionable outlier the top-15 report names — linked from the report/spec.

## Test Scenarios

- Given a cancelled `deploy-fix` push run with `total_count=0` jobs and no in-flight run, when the follower reconciles, then `redrive_deploy_fix=true` is emitted and the `redrive` job dispatches once. `integration` (fixture suite).
- Given the same row re-classified `cancelled-mid-run` (`total_count>0`), when reconciled, then `redrive_deploy_fix=false` and the issue gains the p0 label path unchanged. `integration`.
- Given an eligible row plus a non-stale `in_progress` run at a descendant SHA, when reconciled, then `false` (deferred delivery wins). `integration`.
- Given the redrive job's `if:` weakened (`!= 'false'`, or a second dispatch line), when the shape suite runs, then a named assertion fails. `unit`.
- Given `bearer-curl.sh`/`track.sh` declared, when `ratchet` re-runs, then live shrinks and any DRAIN-REVEAL residue appears as named `new-pair`s to disposition — never silently accepted. `integration`.
- Given an accept row covering only one of two boundary lines for a pair, when `ratchet` runs, then `new-pair` persists (every-boundary-line rule). `integration` — mirrors the Oct-30 learning fixture.
- Property-based: for every row the report's top-15 table lists, a `grep -n` of the cited suite file must hit the named cause-class pattern (evidence pointers are checkable claims, not vibes). `unit`-equivalent verification step at work.

## Implementation Phases

### Phase 0 — Re-verify

`git fetch origin main && git merge-base --is-ancestor` sanity; re-run `python3 -I scripts/ci-pr-affected-replay.py audit --all-refs` for the authoritative boundary set (anchors may have shifted if sibling drains merged).

### Phase 1 — Ratchet repair

Apply dispositions → fixpoint → `--print-baseline` regen → local `ratchet` exit=0.

### Phase 2 — Report

Download ≥4 green merge_group runs' artifacts → median rank → per-suite cause evidence → write audit doc → file outlier issues.

### Phase 3 — Redrive

Script output + workflow job + test rows + runbook + ADR → self-test + suite green.

### Phase 4 — Close-out

spec/tasks/decision-challenges persisted; `Closes #12001` and `Closes #10033` in the PR body (epic #11556 is `Ref` — item 2 completes one lever checkbox, not the epic).

## Alternative Approaches Considered

| Option | Verdict | Why |
|---|---|---|
| Native `concurrency.queue: max` on every `terraform-apply-web-platform-host` member (GitHub, 2026-05-07) | Rejected this slice | Effective only if declared on ALL ≥6 group members (the arriving run's `queue` governs eviction); then every merge-queue merge pays a serialized apply — arrival rate > apply rate during drains grows an unbounded backlog, and the 100-cap evicts *newest* arrivals, recreating the same silent hole plus hours of stale-sha queue. Re-evaluate post-#10033 as a filed follow-up with a measured queue-depth bound. |
| Issue option (b): move the delivery POST out of the shared group | Rejected | The POST is a `local-exec` provisioner of `terraform_data.deploy_pipeline_fix` — delivery and the R2 state write are one apply; splitting requires restructuring the resource graph, and any state write still needs the serializer. |
| Issue option (c): queue-aware retry wrapper in the workflow | Rejected | An evicted pending run executes zero jobs — nothing in-run can observe or retry its own cancellation; an external observer is required, and one already exists (the follower). |
| Auto-dispatch inside the existing `follow` job | Rejected | Violates the shipped "holds no credential beyond the run token" contract and ADR-189's sense/actuation split; a second job scopes `actions: write` to the actuation only. |
| Redrive `infra` rows too | Deferred | The issue names deploy-pipeline-fix; an undelivered infra apply has the same shape but a bigger blast radius — filed as a follow-up after deploy-fix redrive is observed. |
| Human-paste remediation (status quo) | Rejected | That is the defect: during a storm the human is the queue (#10033 measured two manual dispatches evicted). |

## Hypotheses

Network-outage gate fired on the `terraform apply` token (the apply targets carry SSH provisioners). Not applicable as written: this plan diagnoses no connectivity failure and modifies no SSH provisioner, bridge, firewall, or allowlist — the redrive re-uses the existing apply path unchanged. Recorded per `hr-ssh-diagnosis-verify-firewall` with no L3→L7 hypotheses owed.

## Context / Sharp Edges

- A plan whose `## User-Brand Impact` is empty or placeholder fails deepen-plan Phase 4.6 — filled above.
- The `cancelled-mid-run` exclusion is load-bearing: a mid-run cancel can leave partial terraform state on an unlocked backend — auto-applying over it is the split-state the group exists to prevent.
- `lane:` defaulted to `cross-domain` (no `spec.md` on this branch — fail-closed TR2 default; no spec to carry forward from).
- Harness notes: no Task/Skill-spawn tool exists on this Devin pipeline — domain leaders, spec-flow-analyzer, the scoped advisor consult (Step 4.5), and the CPO sign-off consult could not be spawned; each is recorded as a `pending - assumed:` row in `decision-challenges.md` or noted in-line. Functional-overlap discovery (Phase 1.5b) was likewise un-spawnable; the surface is repo-internal machinery with no plausible community equivalent.

## References

- Issues: #12001, #10033, #11556, #10865, #10448, #11954, #10859, #11562, #9938, #11329, #10879, #4844
- Docs: [GitHub concurrency control](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency), [2026-05-07 larger-queues changelog](https://github.blog/changelog/2026-05-07-github-actions-concurrency-groups-now-allow-larger-queues/)
- ADRs: 006 (R2 no state lock), 189 (sense/adjudicate/actuate), 217 (deploy-gate per-SHA), 240 (checked-in shard data), 276 (merge queue full battery), 252, 262
- Brainstorms: `2026-10-12-ci-path-aware-gating`, archived `20261030-170617-2026-10-29-required-check-time`
- Learnings cited inline in Research Insights.
