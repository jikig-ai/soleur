---
title: "fix: bound review shellcheck scanning and split argv bearer sweep"
type: fix
date: 2026-11-27
slug: shellcheck-timeout-argv-sweep-split
branch: feat-one-shot-13098-13099-shellcheck-split
issue: 13098
closes: [13098, 13099]
priority: p1
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
lane: cross-domain
---

## Enhancement Summary

**Deepened on:** 2026-11-28
**Sections enhanced:** 8
**Research agents used:** sequential inline fallback for repo research, learnings research, git-history review, architecture/security/performance/test-design/simplicity/observability review, SpecFlow, and advisor review. This depth-1 harness has no nested Agent/Task fan-out; no independent subagent review is claimed.

### Key Improvements

1. Re-verified the live premises against GitHub and a freshly fetched `origin/main`: both target files are unchanged upstream, while `scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh`, and `plugins/soleur/test/fixture-relative-assert.baseline.txt` moved upstream and require a rebase-aware implementation pass.
2. Measured the split feasibility directly: representative fragments with `# shellcheck shell=bash` complete full ShellCheck analysis in about 1-2 seconds each, while the current monolith hits a 15-second bound.
3. Found and documented upstream ShellCheck evidence that `--extended-analysis=false` avoids the memory blow-up but disables control-flow-dependent checks; the plan keeps full analysis plus fail-closed timeout evidence rather than silently degrading scan strength.
4. Corrected plan drift found by the deepen pass: the open-review overlap is empty, the observability expected output is now a matchable literal, receipt-field semantics are explicit, and the affected-test edge uses the fragment directory population rather than a static member list.

### New Considerations Discovered

- `scripts/test-all.sh` (536,454 bytes) completes ShellCheck in about 10.4 seconds locally even though it exceeds the provisional 512 KiB size prefilter. The size-cap threshold is therefore a genuine technical tradeoff, recorded as pending/assumed in `decision-challenges.md` because this harness cannot spawn the CTO agent.
- ShellCheck upstream documents whole-program dataflow analysis as the memory blow-up mechanism. Local measurement confirms `--extended-analysis=false` lets the monolith finish in about 5 seconds, at the cost of checks such as SC2317/SC2319/SC2324.
- `review-scan-gate.sh` currently creates a first temporary directory and then reassigns `TMP`, orphaning the first directory on normal scans; the implementation phase folds in that one-line cleanup adjacency because the scan loop is already being rewritten.

## Overview

Bound the review scan gate's ShellCheck arm so one oversized or pathological shell input cannot stall the review pipeline, and split the argv-bearer sweep monolith along its existing stage boundaries so ShellCheck, diffs, and review can process it again. The combined change closes #13098 and #13099 while preserving the scan gate receipt contract and the suite's exact test-count floor semantics.

## Research Insights

Reviewed-Coverage: sequential-fallback — this depth-1 Devin harness has no nested Agent/Task fan-out, so the research, domain, SpecFlow, advisor, and plan-review roles prescribed by the canonical skills are run sequentially inline by the orchestrator. No independent subagent review is claimed.

### Premise Validation

- Checked GitHub state on 2026-11-27 and re-checked on 2026-11-28: #13098 and #13099 are OPEN and have no closing PR references; cited PR #13006 is still OPEN and unmerged; cited issue #9294 is still OPEN. The premise is live, not already resolved. Draft PR #13101 is this branch and currently has no closing-issue references.
- Verified on a freshly fetched `origin/main` (069e9371ef) on 2026-11-28: `plugins/soleur/skills/review/scripts/review-scan-gate.sh` exists (276 lines, 6,931 bytes) and `tests/scripts/test-argv-bearer-sweep.sh` exists (8,267 lines, 729,734 bytes). The issue says 8,323 lines; the current tree is already 56 lines shorter, but the size/class defect is unchanged. The two primary target files are byte-identical between the branch merge-base and `origin/main`, so the extraction coordinates remain valid at deepen time; implementation must still re-verify them after the required rebase.
- Upstream movement since the branch merge-base touches `scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh`, and `plugins/soleur/test/fixture-relative-assert.baseline.txt`. These are secondary files in this plan; implementation must rebase before editing them and must not reuse stale hunks blindly.
- Verified the cited scan-gate call site: the script invokes `shellcheck -f json "${shells[@]}"` once with no timeout or per-file bound. ADR-324 currently says ShellCheck `ok` requires the binary to have run with every shell target on its argv, so a per-file execution loop is a decision-record amendment, not a silent implementation detail.
- ADR corpus check: ADR-324 governs the scan receipt; ADR-150 records a prior ShellCheck/actionlint nontermination class and says extraction made ShellCheck able to lint a large body directly; ADR-129 declines repo-wide ShellCheck adoption for unrelated defect classes but does not reject this existing scan arm; ADR-196 is about a different full-gate refusal. No ADR was found that rejects per-file timeouts or splitting this suite.
- Collision precheck for both issues on 2026-11-28 names only this run's own draft PR #13101, which is expected; the foreign `test-all.sh` processes observed during the first planning pass have exited (`foreign=none`).
- CLI verification: local `timeout --help` confirms `timeout [OPTION]... DURATION COMMAND`, `-k/--kill-after`, and timeout signal control; local `shellcheck --version` reports 0.11.0 and `shellcheck --help` confirms `-f json` and `--extended-analysis=bool` support.

### Property List

1. The review scan gate must always terminate with its documented receipt contract, even when one shell input is pathological.
2. Every classified shell input must either be actually scanned or make the receipt fail closed; an `ok` receipt must never silently omit coverage.
3. A timeout or oversize input must produce operator-visible evidence naming the input and reason, not a silent skip or an unbounded process.
4. The argv-bearer suite must be split into ShellCheck-processable fragments without changing row execution order, shared counters, or the exact `EXPECTED_TESTS` floor semantics.
5. The split must preserve the floor-history convention and the suite's hermetic properties: synthesized fixtures only, no network, no real credential reads.
6. The combined diff must keep the review scan gate's ADR-324 evidence model honest: scanned means scanned, and unscannable means refusal rather than a clean-scan claim.

### Cut List

- No new autonomous scheduler, cron, workflow, or service — buys no property in the list; the defect is local scan/test machinery and existing local scripts cover it.
- No repo-wide ShellCheck adoption expansion — ADR-129 already declined that unrelated adoption; the existing review scan arm is the only scan surface in scope.
- No rewrite of the argv-bearer assertions — the ask is a structural split preserving behavior, not a redesign of the security battery.
- No memory-cgroup or containerization mechanism — a memory bound buys protection but adds platform-specific machinery; the requested timeout plus size bound covers the pipeline-wedge property with less mechanism.
- No independent per-fragment test runner — fragments share counters and helpers by design; a driver preserving the original source order covers the property with less behavior risk.

### Repository Research Summary

#### Architecture & Structure

- Review scan authority: `plugins/soleur/skills/review/scripts/review-scan-gate.sh` classifies inputs into `sources` and `shells`, invokes Semgrep for source files, invokes ShellCheck once for every shell file, prints `SOLEUR_REVIEW_SCAN_GATE`, and exits through `refuse`/`skip`/`ok` tokens.
- Receipt consumers: `plugins/soleur/skills/review/SKILL.md` requires the scan gate before every review seat; `plugins/soleur/agents/engineering/review/semgrep-sast.md` and `security-sentinel.md` quote the receipt rather than rerunning scanners; `apps/web-platform/server/git-lock-marker-telemetry.ts` mirrors the marker but does not page it.
- Existing scan-gate tests: `plugins/soleur/skills/review/test/review-scan-gate.test.sh` is hermetic, stubs Semgrep and ShellCheck, and currently has 34-ish contract assertions plus skill/agent drift checks. It already verifies that ShellCheck receives shell targets and that missing ShellCheck refuses.
- The argv-bearer suite is explicitly registered, not auto-discovered: `scripts/test-all.sh` registers `tests/scripts/argv-bearer-sweep` as `bash tests/scripts/test-argv-bearer-sweep.sh`; `scripts/suite-shard-legs.tsv` and `scripts/suite-durations.tsv` already know the review-scan-gate suite.
- `scripts/lib/test-affected-paths.sh` contains affected-edge references to `tests/scripts/test-argv-bearer-sweep.sh` and comments citing its stage census; the split must either keep the driver path stable or update those references deliberately.

#### Measured File Shape

Current contiguous byte/line measurements of `tests/scripts/test-argv-bearer-sweep.sh`:

| Segment | Lines | Bytes |
|---|---:|---:|
| prelude/harness + controls | 1-929 | 55,831 |
| stage 2 manifest | 930-1166 | 20,611 |
| stage 3 infra scripts | 1167-1365 | 15,489 |
| stage 4 shim extensions | 1367-1572 | 16,500 |
| stage S2-A backup+HMAC | 1574-2753 | 103,083 |
| stage S2-B Better Stack | 2755-3101 | 27,661 |
| stage S2-C deploy webhook | 3103-3435 | 31,256 |
| stage S3 workflow yaml | 3437-3867 | 41,861 |
| stage S4 production files | 3869-5566 | 175,498 |
| stage S5 apply/registry | 5568-6201 | 58,843 |
| stage S6 htpasswd | 6203-6578 | 33,550 |
| stage S6-HB heartbeat | 6580-6869 | 28,427 |
| stage S7 markdown | 6871-7505 | 57,922 |
| stage S8 registry login | 7507-7908 | 29,458 |
| stage S9 terraform vars | 7910-8206 | 25,518 |
| verdict/floor | 8207-8267 | 7,170 |

The file has no single uniform 80-100 KB cut: most natural stages are 15-60 KB, S2-A is 103 KB, and S4 is 175 KB. A split that combines small neighboring stages and divides S2-A/S4 at their existing internal part boundaries can stay near the requested size range without inventing new semantic boundaries.

#### Shell Input Size Evidence

`git ls-files '*.sh` currently yields 1,988 shell files. Largest sizes include `apps/web-platform/infra/ci-deploy.test.sh` (907,186 bytes), `tests/scripts/test-argv-bearer-sweep.sh` (729,734), `scripts/test-all.sh` (536,454), `apps/web-platform/infra/ci-deploy.sh` (422,652), and `apps/web-platform/infra/cutover-inngest-workflow.test.sh` (399,438). Counts above candidate caps: 197 files over 64 KiB, 61 over 128 KiB, 12 over 256 KiB, 3 over 512 KiB.

Deepen-pass local probes on 2026-11-28, all with full default ShellCheck analysis and a 15-second `timeout -k 2s` envelope: `apps/web-platform/infra/ci-deploy.sh` completed in 9.09s with rc=1 (findings); `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` completed in 4.32s with rc=1; `scripts/test-all.sh` completed in 10.43s with rc=1 despite exceeding 512 KiB; `apps/web-platform/infra/ci-deploy.test.sh`, `apps/web-platform/infra/cutover-inngest-workflow.test.sh`, and the argv-bearer monolith hit the 15-second bound. This proves size alone is an imperfect predictor: the provisional 512 KiB cap would refuse one actively edited file that can complete. The timeout is therefore the semantic bound; the size prefilter remains a provisional technical tradeoff rather than established fact.

A deepen-pass extraction probe prepended only `# shellcheck shell=bash` to representative planned fragments and ran full ShellCheck analysis: fragment 01 (94,525 bytes) completed in about 2s with 32 findings; fragment 05 (91,388) in about 1s with 68 findings; fragment 06 (84,246) in about 2s with 38 findings; fragment 10 (55,176) in about 1s with 67 findings. This establishes the split feasibility point: fragments are individually parseable and complete quickly, but the plan must disclose pre-existing warning/style noise rather than rewriting assertions to silence it.

Upstream ShellCheck issue [koalaman/shellcheck#3177](https://github.com/koalaman/shellcheck/issues/3177) identifies whole-program iterative dataflow analysis as the memory blow-up mechanism; the maintainer says `--extended-analysis=false` drops the excessive time/memory while disabling control-flow-dependent checks such as SC2317, SC2319, and SC2324. Local confirmation: the current monolith finished in about 5s with rc=1 when run with `--extended-analysis=false`. The plan does **not** silently adopt that flag because it weakens scan evidence; any degraded-analysis fallback is a separate technical ruling. The default remains full analysis plus timeout/refusal.

### Institutional Learnings

- `2026-11-20-a-shell-mirror-of-an-app-rule-diverged-on-trim-json-strictness-and-exit-status.md`: local ShellCheck was OOM-killed on a saturated host; recovery sent the scan leg to CI; the scan gate also mis-resolved relative worktree paths. Planning must keep paths absolute/repo-stable and avoid claiming local success is sufficient under host saturation.
- `2026-07-27-a-check-that-cannot-report-is-indistinguishable-from-one-that-passed.md`: a linter that hangs presents as still working; ShellCheck/actionlint nontermination was pre-existing and invisible until isolated. This directly supports fail-closed timeout receipts.
- ADR-150: a 117,954-byte workflow step hung actionlint's ShellCheck integration at the pipe-buffer boundary; extraction let ShellCheck lint the script directly. This is prior art for splitting large shell bodies rather than waiting for the tool to scale.
- `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`: guards need mutation rows that can drive them red, including their own dispatch. The scan-gate timeout/cap and the split driver both need mutation-matrix coverage.
- `2026-10-06-an-argv-bearer-sweep-needed-a-ratchet-a-token-shape-guard-and-a-process-substitution-not-a-pipe.md`: the argv-bearer suite exists to prevent credential-on-argv regressions; structural cleanup must not weaken its census, mutation, or exact-floor properties.

### Functional Overlap / Community Discovery

- No uncovered non-TypeScript/Rails stack signatures were detected, so the community stack-gap check did not spawn.
- Registry queries for `shellcheck timeout` returned zero skills in `api.claude-plugins.dev`; a broad CI/CD plugin in `claudepluginhub` does not implement bounded ShellCheck scan receipts or argv-bearer suite splitting; the Anthropic marketplace scan found no matching overlap. Nothing installed.
- External best-practices research is skipped: the change is repo-specific machinery with strong local contracts, ADRs, tests, and measurements. Local CLI help is used to verify prescribed flags.

### Hypotheses

The word `timeout` triggered the network-outage checklist, but the measured incident is local CPU/memory exhaustion in a scanner process, not network connectivity. Required layer entries, in L3-to-L7 order:

1. **L3 firewall allow-list drift** — opted out: not applicable to a local `shellcheck` parse/analysis process; verification artifact is #13098's measured CPU/RSS growth on the local box.
2. **L3 DNS/routing** — opted out: no hostname or network path participates in the scan; verification artifact is the local invocation in `review-scan-gate.sh`.
3. **L7 TLS/proxy layer** — opted out: no HTTPS endpoint participates in the scan; verification artifact is the local invocation in `review-scan-gate.sh`.
4. **L7 application/service layer** — verified by shape rather than host logs: the affected service is the scan gate process itself; evidence is the unbounded `shellcheck -f json` call and issue-measured nontermination.
5. **Primary hypothesis** — one or more very large/complex shell inputs drive superlinear ShellCheck analysis; a single multi-file invocation means one input can starve or wedge the entire receipt.
6. **Secondary hypothesis** — splitting the monolith reduces input size enough for ShellCheck to complete, while per-file timeout/size classification bounds the residual pathological-input class.

## Problem Statement

The review pipeline's deterministic scan gate is fail-closed only after it returns. Its ShellCheck arm currently cannot be trusted to return: one multi-file invocation has no time or input-size bound, so a pathological shell file can consume unbounded CPU/RSS and prevent the `SOLEUR_REVIEW_SCAN_GATE` receipt from ever being printed. That is worse than a refusal because the review phase stalls before any seat starts.

The argv-bearer conversion battery is the known pathological input. It is a 729,734-byte monolith whose assertions are valuable but whose shape defeats the toolchain: ShellCheck does not complete on it, diffs are unreadable, and each new stage accretes into the same file. The two defects are coupled and must land together: bounding the scanner prevents a pipeline wedge in general, while splitting the suite removes the current input that triggers the wedge.

## Proposed Solution

1. Change the ShellCheck arm of `review-scan-gate.sh` from one unbounded multi-file invocation to a per-file bounded loop. Each shell file is scanned with full default analysis via `timeout -k 5s 30s shellcheck -f json -- <file>` (or `gtimeout` on hosts where that is the coreutils binary). A file larger than 512 KiB is not scanned. A timeout, oversize input, malformed scanner output, missing timeout binary, or unexpected scanner status makes the gate emit `refuse` with trailing `scanned=<n> unscannable=<n>` fields and a `file:0 unscannable-timeout` or `file:0 unscannable-size` evidence row. `files=` remains the classified target count; `scanned=` counts shell files ShellCheck actually completed on. Shell-involving `ok` receipts carry the same two fields so consumers can audit coverage directly; `ok` is possible only when every classified shell file was scanned and `unscannable=0`.
2. Preserve scan findings as non-blocking `file:line rule-id` rows. Real ShellCheck findings still do not stop review; unscannable inputs do stop review because coverage evidence would otherwise be false.
3. Rewrite `tests/scripts/test-argv-bearer-sweep.sh` as the stable driver for the same suite registration. The driver keeps the core harness/prelude and final verdict inline, sources ten fragments in exact original order, and preserves the global `pass`/`fail`/`CASES` counters and reporting helpers by sourcing in one shell process.
4. Embed a small structural preamble in the driver proving that it sources every tracked fragment exactly once, in dependency order, and that no source statement is conditional. Keeping this check inside the already-registered suite avoids editing the oversize `scripts/test-all.sh` runner in the same PR that makes the scan gate refuse oversize shell inputs. The exact row-count floor remains the behavioral anti-truncation guard.
5. Amend ADR-324 in the same PR because the execution evidence changes from one argv containing every shell target to a per-file completion set whose receipt accounts for `scanned` and `unscannable`.

## Technical Approach

### Scan-gate contract

- Resolve a timeout binary once: `timeout` first, `gtimeout` second; refuse when neither exists.
- Use 30 seconds as the per-file wall-clock budget and a 5-second kill grace (`timeout -k 5s 30s shellcheck -f json -- "$file"`; `--` is supported by local ShellCheck 0.11.0 and prevents path-shaped option injection). Evidence: the 422,652-byte `ci-deploy.sh` completed in 9.09s, the 261,363-byte `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` in 4.32s, and the 536,454-byte `scripts/test-all.sh` in 10.43s during full-analysis deepen probes; 30s is roughly 3x the slower measured completion while avoiding the issue's example of a two-minute stall per file.
- Do not pass `--extended-analysis=false` in the default scan. Upstream and local evidence says it avoids the memory blow-up, but it disables control-flow-dependent checks; a degraded-analysis fallback would need an explicit receipt marker and a CTO ruling, and is out of this plan's default.
- Repair the adjacent double-`mktemp` defect while rewriting this block: the current script creates one temporary directory before `--probe` handling and then reassigns `TMP`, orphaning the first directory on every normal scan. Keep one tempdir owner and one cleanup trap.
- Use 512 KiB (524,288 bytes) as the provisional size bound. Evidence: only three tracked shell files exceed it, including the 729,734-byte pathological monolith and the 907,186-byte `ci-deploy.test.sh`; the 422,652-byte production script completed in 9.09s. Counterevidence: the 536,454-byte `test-all.sh` also exceeds the cap yet completed in 10.43s, so the cap is a conservative complexity/memory prefilter rather than a nontermination predictor. The timeout remains the semantic bound, and the cap choice is recorded as pending/assumed pending CTO availability.
- Preserve the existing rc=0/rc=1 ShellCheck distinction: both mean the process completed; rc=1 carries findings. Timeout statuses (notably 124 and kill-mediated 137) and all other unexpected statuses fail closed.
- Aggregate findings across per-file JSON arrays without concatenating raw arrays as one document. Each completed file's JSON is parsed independently and normalized into the existing `file:line rule-id` output.
- Keep paths as supplied by the caller, but document/verify that the review skill passes repo-worktree paths. Do not reimplement the unrelated relative-path defect tracked in #12779.

### Suite split shape

The driver remains `tests/scripts/test-argv-bearer-sweep.sh`, so `scripts/test-all.sh`'s suite command and existing external references continue to name a real executable suite. The driver retains lines equivalent to the current core harness/prelude (the shebang, strict mode, stdin closure, counters, scratch root, shim, helper functions, canned bodies) and the final verdict/floor block. It sources exactly ten fragments:

| Fragment | Source span / content | Approx. bytes |
|---|---|---:|
| `tests/scripts/argv-bearer-sweep/01-controls-stages-2-4-s2a-backup.sh` | exact lines 599-1776: instrument controls, synthetic mutation/evaluate controls, stages 2-4, S2-A part 1 | 94,501 |
| `tests/scripts/argv-bearer-sweep/02-s2a-hmac.sh` | exact lines 1777-2753: S2-A part 2 HMAC/copy rows | 87,765 |
| `tests/scripts/argv-bearer-sweep/03-s2b-s2c.sh` | exact lines 2754-3435: Better Stack and deploy-webhook stages | 59,093 |
| `tests/scripts/argv-bearer-sweep/04-s3-workflow.sh` | exact lines 3436-3867: workflow YAML stage | 41,949 |
| `tests/scripts/argv-bearer-sweep/05-s4-through-guard2-row12.sh` | exact lines 3868-4813: S4 instrument/census/parity plus Guard 2 rows through 12 | 91,364 |
| `tests/scripts/argv-bearer-sweep/06-s4-guard2-rows13-24.sh` | exact lines 4814-5566: S4 Guard 2 rows 13-24, shapes, replay | 84,222 |
| `tests/scripts/argv-bearer-sweep/07-s5-apply-registry.sh` | exact lines 5567-6201: S5 apply workflow and registry rows | 58,931 |
| `tests/scripts/argv-bearer-sweep/08-s6-heartbeat.sh` | exact lines 6202-6869: S6 htpasswd plus S6-HB heartbeat rows | 62,153 |
| `tests/scripts/argv-bearer-sweep/09-s7-markdown.sh` | exact lines 6870-7505: S7 markdown rows | 58,010 |
| `tests/scripts/argv-bearer-sweep/10-s8-s9.sh` | exact lines 7506-8206: S8 registry login plus S9 terraform rows | 55,152 |

The ten ranges are disjoint, contiguous, and cover every byte of lines 599-8206 exactly once (693,140 bytes total). The driver retains lines 1-598 plus lines 8207-8267. Line numbers are planning-time extraction coordinates against branch `HEAD`, not permanent content anchors; implementation must re-verify the boundary text before cutting if the file changes under rebase. Precedent-diff gate: no existing sourced-fragment driver pattern was found in the repo's test/script corpus, so this topology is novel and receives explicit structural verification rather than claiming parity with a sibling.

Each fragment begins with `# shellcheck shell=bash` and a comment stating that it is sourced by the driver and is not independently runnable. No fragment gets its own counters, scratch root, trap, network access, or credential access. Source order is the original execution order. Extraction must be mechanical from the pre-split file, with a normalization-aware comparison back to `HEAD` proving that only the driver source statements and fragment headers differ.

### Structural verification

Embed the structural preamble in `tests/scripts/test-argv-bearer-sweep.sh` before the first fragment source. It derives the tracked fragment population with `git ls-files 'tests/scripts/argv-bearer-sweep/*.sh'`, parses the driver's unconditional `source` statements, and asserts exact set-and-order equality. Its mutation matrix covers a missing fragment, an extra fragment, a reorder, a conditional source, and a second source of one fragment. It is deliberately not a separate `test-*.sh` suite: registering one would require editing `scripts/test-all.sh`, currently 536,454 bytes and therefore an unscannable input under this PR's own 512 KiB scan-gate prefilter. Running the structural check inside the existing argv-bearer suite preserves coverage without creating that self-refusal.

## Implementation Phases

### Phase 1: Failing contracts first

- Extend `plugins/soleur/skills/review/test/review-scan-gate.test.sh` with hermetic failing rows before editing the gate: per-file invocation order, a hanging ShellCheck stub classified as timeout, an oversize fixture refused without invoking ShellCheck, a missing timeout binary refusal, scanner output aggregation across two files, and proof that an `ok` receipt is impossible when any input is unscannable.
- Add the driver-embedded structural contract in RED form before the split: the current monolith fails because the fragment directory is absent and the required source manifest does not yet exist.
- Success criteria: the new tests fail for the intended reason against the unmodified tree; no production/test script code has yet been changed.

### Phase 2: Bound the scan gate

- Implement the per-file timeout/size loop in `review-scan-gate.sh`.
- Update `plugins/soleur/skills/review/SKILL.md` and the receipt consumers only as needed to document `scanned=`/`unscannable=` and the fail-closed unscannable semantics.
- Amend ADR-324's Decision/Consequences in place.
- Success criteria: the hermetic scan-gate suite is green; a hanging stub never outlives the configured bound; findings from two completed shell files aggregate in input order.

### Phase 3: Mechanically split the argv-bearer suite

- Extract the ten fragments from the current monolith using exact contiguous line ranges, with no assertion rewrite.
- Rewrite the monolith path as driver retaining core harness/prelude plus verdict/floor and unconditional source statements.
- Update affected-test edge declarations with the fragment directory prefix `tests/scripts/argv-bearer-sweep/` rather than a static list of today's ten members, update the trio baseline keys that move with fragment content, and update any fixture-relative baseline rows measured by the committed regeneration command.
- Success criteria: structural extraction comparison passes; `bash tests/scripts/test-argv-bearer-sweep.sh` prints the same `=== 832 passed, 0 failed ===` row count as the pre-split oracle; `EXPECTED_TESTS=832` remains exact.

### Phase 4: Cross-verification and documentation

- Run `shellcheck` with a bounded timeout on the driver and every fragment; the completion property is the acceptance target even when pre-existing warning findings remain.
- Run the focused scan-gate suite and the argv-bearer suite (including its structural preamble). The foreign full-battery processes observed in the first planning pass have exited; re-check before implementation and use focused suites plus CI if new contention appears.
- Success criteria: scan gate no longer wedges when handed the split suite paths; review receipt remains fail-closed on a synthetic hanging input.

## Alternative Approaches Considered

| Alternative | Decision | Rationale |
|---|---|---|
| Keep one ShellCheck invocation and wrap only that invocation in `timeout` | Rejected | One timeout still cannot identify the pathological file cleanly, loses findings for every later file, and does not bound memory before the timeout. |
| Mark unscannable files as warnings but emit `ok` | Rejected | ADR-324's evidence contract would become false: `ok` would no longer mean every classified shell input was scanned. |
| Size cap at 128 or 256 KiB | Rejected as overbroad | 61 or 12 tracked shell files would be refused, including measured files that complete; 512 KiB catches the three extreme inputs while timeout covers nonlinear smaller cases. |
| No size cap, timeout only | Rejected provisionally | It is simpler and avoids false refusals, but a known 730 KB input would still burn up to the full timeout and memory budget on every review that touches it. The cap is cheap disclosure before analysis starts. Deepen evidence shows the cap is a genuine tradeoff (`scripts/test-all.sh` completes despite exceeding 512 KiB), so this row remains tied to the pending CTO-ruling assumption rather than a settled certainty. |
| Scan with `--extended-analysis=false` | Rejected for this plan | It makes the monolith finish locally in about 5s, but upstream says control-flow-dependent checks such as SC2317/SC2319/SC2324 no longer fire. Silent degradation would make the scan evidence weaker than the receipt implies; any explicit degraded-analysis fallback is a separate CTO-ruled design. |
| Split into independently runnable suites | Rejected | The issue itself notes shared counters/helpers; duplicating harness setup or inventing per-fragment counter plumbing is higher risk than ordered sourcing in one process. |
| Keep the monolith and add `# shellcheck disable=all` | Rejected | #13098 measured that this does not help because parse/analysis cost occurs before checks are disabled. |
| Defer ADR-324 amendment | Rejected | The plan changes scan-evidence semantics; recorded architecture must not lag the change. |

## Files to Edit

- `plugins/soleur/skills/review/scripts/review-scan-gate.sh` — per-file bounded ShellCheck scanning and unscannable accounting.
- `plugins/soleur/skills/review/test/review-scan-gate.test.sh` — hermetic receipt-contract rows.
- `plugins/soleur/skills/review/SKILL.md` — receipt semantics and unscannable interpretation.
- `plugins/soleur/agents/engineering/review/semgrep-sast.md` — quote the amended zero-finding receipt contract rather than the pre-timeout contract.
- `plugins/soleur/agents/engineering/review/security-sentinel.md` — quote the amended zero-finding receipt contract rather than the pre-timeout contract.
- `knowledge-base/engineering/architecture/decisions/ADR-324-review-scan-evidence-is-the-orchestrator-read.md` — amend per-file completion evidence.
- `tests/scripts/test-argv-bearer-sweep.sh` — rewrite as stable driver.
- `tests/scripts/trio-baseline.tsv` — move the affected baseline keys only when their owning content moves into fragments.
- `plugins/soleur/test/fixture-relative-assert.baseline.txt` — regenerate deliberately if the split changes measured rows.
- `scripts/lib/test-affected-paths.sh` — add the fragment directory prefix `tests/scripts/argv-bearer-sweep/` to the argv-bearer affected-edge population and re-anchor stale line-number comments to content anchors while touching that edge block.

## Files to Create

- `tests/scripts/argv-bearer-sweep/01-controls-stages-2-4-s2a-backup.sh`
- `tests/scripts/argv-bearer-sweep/02-s2a-hmac.sh`
- `tests/scripts/argv-bearer-sweep/03-s2b-s2c.sh`
- `tests/scripts/argv-bearer-sweep/04-s3-workflow.sh`
- `tests/scripts/argv-bearer-sweep/05-s4-through-guard2-row12.sh`
- `tests/scripts/argv-bearer-sweep/06-s4-guard2-rows13-24.sh`
- `tests/scripts/argv-bearer-sweep/07-s5-apply-registry.sh`
- `tests/scripts/argv-bearer-sweep/08-s6-heartbeat.sh`
- `tests/scripts/argv-bearer-sweep/09-s7-markdown.sh`
- `tests/scripts/argv-bearer-sweep/10-s8-s9.sh`

## User-Brand Impact

- **If this lands broken, the user experiences:** a Soleur review or one-shot pipeline that stalls before review seats, or a false clean-scan receipt that lets a shell-security defect pass review.
- **If this leaks, the user's [data / workflow / money] is exposed via:** workflow exposure rather than data exposure — credential-bearing shell changes could evade deterministic review if unscannable inputs are misreported as scanned.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** this is internal review machinery with no direct end-user data path; the impact is developer workflow integrity, not a single-user production incident.

*Scope-out override:* `threshold: none, reason: the touched paths are test/review machinery and synthesized fixtures, not user data, auth, production API, or billing surfaces.`

## Observability

```yaml
liveness_signal:
  what: SOLEUR_REVIEW_SCAN_GATE receipt emitted by the scan gate
  cadence: per review invocation
  alert_target: review orchestrator / CI red check
  configured_in: plugins/soleur/skills/review/scripts/review-scan-gate.sh
error_reporting:
  destination: review orchestrator stdout and CI job output
  fail_loud: SOLEUR_REVIEW_SCAN_GATE refuse with scanned/unscannable counts or a non-zero focused-suite result
failure_modes:
  - mode: ShellCheck hangs on one input
    detection: timeout status produces an unscannable-timeout row and refuse receipt
    alert_route: review phase stops before seats; CI red if exercised in test
  - mode: oversized shell input enters the diff
    detection: size prefilter produces an unscannable-size row and refuse receipt
    alert_route: review phase stops before seats; CI red if exercised in test
  - mode: argv-bearer fragment omitted or source order drift
    detection: driver structural exact set/order assertion plus EXPECTED_TESTS exact floor
    alert_route: scripts/test-all.sh red suite
logs:
  where: review orchestrator stdout, focused suite output, and CI logs
  retention: CI retention policy; local session lifetime
discoverability_test:
  command: bash plugins/soleur/skills/review/scripts/review-scan-gate.sh --probe
  expected_output: SOLEUR_REVIEW_SCAN_GATE
```

## Architecture Decision (ADR/C4)

### ADR

Amend `knowledge-base/engineering/architecture/decisions/ADR-324-review-scan-evidence-is-the-orchestrator-read.md` in this PR. The amendment states that ShellCheck evidence is a per-file completion set bounded by timeout/size classification; `ok` requires `scanned` equal to the classified shell count and `unscannable=0`; timeout/oversize inputs are measured refusals, not silent findings-free scans.

### C4 views

No C4 impact. Checked the actor/system/relationship rubric against all three model files: no new external human actor, external vendor/system, container/data store, or actor-to-surface access relationship is introduced. The change is internal behavior of the existing local review-scan tooling. The implementation pass must still run the C4 validation tests if any `.c4` file is touched; none is planned.

### Sequencing

The ADR amendment lands in the same commit series as the scan-gate contract change, before review.

## Guard Contract

### Guard 1 — bounded ShellCheck scan receipt

**Property.** Every classified shell input either completes ShellCheck within the declared timeout/size envelope and contributes its findings, or the scan gate emits a fail-closed `refuse` receipt naming that input as unscannable.

**Assembly.** The chokepoint is the single ShellCheck arm in `plugins/soleur/skills/review/scripts/review-scan-gate.sh`, through which every shell path classified from the review range must pass; the contract covers the timeout-binary resolution, size prefilter, per-file invocation loop, per-file JSON parsing, receipt emission, and evidence rows.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove the timeout wrapper from the per-file invocation while using a hanging ShellCheck stub | RED |
| 2 | Raise the size comparison so an oversize fixture is scanned rather than classified | RED |
| 3 | Make the loop stop after the first shell input when a compliant first input is followed by a second input | RED |
| 4 | Emit `ok` when `unscannable > 0` | RED |
| 5 | Count a classified input in `files` without attempting or accounting for it in `scanned`/`unscannable` | RED |
| 6 | Harness mutation: the ShellCheck stub records no invocation; the suite must not report a scan as green | RED |
| 7 | Must-pass input: two small shell files, one with a finding and one clean, both complete; receipt is `ok` with `unscannable=0` and both finding rows survive | PASS |

**Anchor.** The receipt is anchored in stdout and pinned by the hermetic suite; weakening both script and test in one diff is constrained by independent review and the ADR-324 contract, not by the count alone.

### Guard 2 — argv-bearer split driver completeness

**Property.** The stable driver sources exactly the tracked argv-bearer fragment set once each, unconditionally and in dependency order, while preserving one shared counter/verdict process and the exact test-count floor.

**Assembly.** The chokepoints are the driver `tests/scripts/test-argv-bearer-sweep.sh` (the only suite entry point), the structural preamble in that driver, the source manifest in that driver, the tracked fragment glob `tests/scripts/argv-bearer-sweep/*.sh`, and the final `EXPECTED_TESTS` verdict. There is intentionally no second registered suite because the runner itself is oversize under the scan-gate prefilter.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete one source statement while leaving the fragment tracked | RED |
| 2 | Add a tracked fragment without sourcing it (the guard's own dispatch/population check) | RED |
| 3 | Source the first compliant fragment and stop before the second | RED |
| 4 | Reorder two fragments whose helper definitions are order-sensitive | RED |
| 5 | Make a source statement conditional so the static manifest looks present but runtime order can omit it | RED |
| 6 | Harness mutation: structural preamble accepts zero fragments as a valid population or its invocation is removed while a fragment disappears | RED |
| 7 | Must-pass input: the real driver and the exact tracked fragment set in original order | PASS |

**Anchor.** The exact `EXPECTED_TESTS` floor is a stored value in the same commit, so it is paired with set identity: the driver-embedded structural preamble compares the fragment set and order rather than trusting the count alone.

## Open Code-Review Overlap

None. The deepen pass re-ran the prescribed two-stage open `code-review` issue query on 2026-11-28 against every planned edit/create path, including the fragment directory examples; no issue body matched. Open issue #7942 mentions `scripts/test-all.sh`, but that file is deliberately not in this plan's file list, so it is contextual rather than an overlap and remains open for its own cycle.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 (#13098) | "Per-file `timeout` (e.g. `timeout 120 shellcheck -f json <file>`) looped over `shells[@]`, aggregating JSON; a timed-out file emits a dedicated `refuse`-adjacent receipt token or a documented `unscannable` row in the findings output rather than hanging the whole gate." | FR-1 / Phase 2 / `review-scan-gate.sh` | mapped |
| 2 (#13098) | "Optionally a size cap marking files >N bytes `unscannable` with disclosure in the receipt." | FR-2 / Phase 2 / `review-scan-gate.sh` | mapped |
| 3 (#13099) | "Split along the existing stage boundaries (`stage S1` … `stage S9` + the verdict/floor block) into ~8-10 fragments of ~80-100KB" | FR-3 / Phase 3 / ten fragments + driver | mapped |
| 4 (#13099) | "Constraint: fragments share `pass`/`fail`/`CASES` and the reporting helpers (`row`, `s9_*`, etc.) — they are not independently runnable suites. Use a driver that `source`s fragments, or per-fragment counters plumbed back." | FR-4 / driver architecture / structural preamble | mapped |
| 5 (#13099) | "Keep `EXPECTED_TESTS` floor semantics and the floor-history comment convention (each PR's delta + measured count)." | FR-5 / verdict retention / AC | mapped |
| 6 (#13099) | "Verify: suite green at the same row count; `shellcheck` completes on every fragment (the point of the split); the scan gate (#13098) no longer wedges on diffs touching this suite." | FR-6 / Phase 4 / Acceptance Criteria | mapped |
| 7 | "[brief] #13098, #13099 in one PR" | Single combined PR scope | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Per-file timeout loop | "Per-file `timeout` … looped over `shells[@]`, aggregating JSON" | asked |
| Oversize classification | "Optionally a size cap marking files >N bytes `unscannable` with disclosure in the receipt." | asked |
| Fail-closed `refuse` on unscannable | "a dedicated `refuse`-adjacent receipt token or a documented `unscannable` row" | inferred — justification: an `ok` receipt would falsely certify unscanned coverage under ADR-324; fail-closed is the strict reading of the cited ask |
| Ten sourced fragments | "Split along the existing stage boundaries" | asked |
| Driver preserving shared counters | "Use a driver that `source`s fragments" | asked |
| Structural source-manifest suite | "they are not independently runnable suites" | inferred — justification: without a set/order guard, a fragment can be omitted while extraction prose still looks correct |
| ADR-324 amendment | — | inferred — justification: the scan-evidence contract itself changes; architecture records must not lag the implementation |
| `scripts/lib/test-affected-paths.sh` update | — | inferred — justification: otherwise edits to new fragments may not select the suite that covers them; the edge uses the directory prefix because the fragment population is derived, not a fixed member list |
| receipt-consumer agent updates | — | inferred — justification: `semgrep-sast` and `security-sentinel` state the zero-finding evidence contract and must not keep quoting the pre-amendment shape |
| double-`mktemp` repair | — | inferred — justification: the scan loop rewrite owns the tempdir lifecycle it depends on; leaving a known orphaned directory in the same block would be a false cleanup claim |
| driver-embedded structural preamble instead of a separately registered suite | — | inferred — justification: embedding avoids a new registration surface and keeps the source-manifest check beside the only supported suite entry point; under the provisional 512 KiB cap it also avoids editing oversize `scripts/test-all.sh` in this PR |
| baseline updates | — | inferred — justification: keyed baselines must move with the content or their census guards red/stale |
| single PR despite large diff | "#13098, #13099 in one PR" | asked |

### Split Assessment

- Subsystems touched: 4 — `plugins/soleur`, `tests`, `scripts`, `knowledge-base`
- Planned files: 18 | Estimated changed lines: ~17,000 (mostly mechanical move lines)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split mechanically indicated — overridden by the explicit brief "#13098, #13099 in one PR" and by atomic coupling: the scan-gate bound and the removal of its current pathological input are one remediation. The diff must make the mechanical split easy to review through exact extraction evidence.

## Acceptance Criteria

### Functional Requirements

- [ ] FR-1. `review-scan-gate.sh` invokes ShellCheck at most once per shell input, with a 30-second timeout and 5-second kill grace via `timeout` or `gtimeout`; no single input can prevent receipt emission.
- [ ] FR-2. A shell input over 524,288 bytes is classified `unscannable-size` without invoking ShellCheck on it; a timeout is classified `unscannable-timeout`; either condition yields a `refuse` receipt carrying `scanned=` and `unscannable=` plus an evidence row naming the file.
- [ ] FR-3. A shell-involving `ok` receipt carries `scanned=` and `unscannable=`, and is emitted only when every classified shell input completed ShellCheck and `unscannable=0`; completed rc=0/rc=1 results still aggregate findings as `file:line rule-id` rows.
- [ ] FR-4. `tests/scripts/test-argv-bearer-sweep.sh` remains the registered suite entry point and sources exactly ten fragments in original dependency order; fragments share the same `pass`, `fail`, `CASES`, `row`, scratch, shim, and helper state in one shell process.
- [ ] FR-5. The split is mechanically faithful: apart from driver source statements and fragment header comments, extracted fragment content matches the pre-split contiguous ranges; no assertion body is rewritten intentionally.
- [ ] FR-6. `EXPECTED_TESTS` remains exact for the measured post-split row count (currently 832 unless implementation evidence proves a harness-only count change), and the floor-history comment gains this PR's measured entry.
- [ ] FR-7. `shellcheck` completes under a bounded timeout on the driver and every fragment; completion is required even when pre-existing warning/style findings remain disclosed.
- [ ] FR-8. The driver-embedded structural preamble derives the tracked fragment population and verifies exact set/order/unconditional sourcing before the first fragment executes.
- [ ] FR-9. ADR-324 is amended in the same PR and no C4 model edit is made unless implementation discovers a modeled external actor/system relationship that planning missed.
- [ ] FR-10. `plugins/soleur/skills/review/SKILL.md`, `plugins/soleur/agents/engineering/review/semgrep-sast.md`, and `plugins/soleur/agents/engineering/review/security-sentinel.md` document unscannable semantics, and zero-finding SAST claims require an `ok` receipt with both `findings=0` and `unscannable=0`.

### Non-Functional Requirements

- [ ] NFR-011 automated functional testability: focused hermetic suites cover the new contract without network or credentials.
- [ ] NFR-007 resilience: pathological scanner input degrades to a bounded refusal instead of a pipeline wedge.
- [ ] NFR-015 documentation of internal services: review-skill prose and ADR-324 agree with implementation.
- [ ] NFR register assessment: no latency, throughput, scaling, data-retention, encryption, or external-service NFR is materially affected.

### Quality Gates

- [ ] New scan-gate tests were written and observed RED before implementation.
- [ ] New structure-suite tests were written and observed RED before the split.
- [ ] Focused suites green: scan-gate contract, argv-bearer structure, argv-bearer conversion battery.
- [ ] ShellCheck completion evidence is recorded for driver plus all ten fragments.
- [ ] `markdownlint`/relevant shell lints on edited docs/scripts as prescribed by `work`.

## Test Scenarios

### Acceptance Tests (RED phase targets)

- Given one small shell file and a ShellCheck stub that exits 0, when the gate runs, then the receipt is `ok`, `scanned=1`, `unscannable=0`, and the stub saw exactly one invocation. [unit]
- Given two shell files where the first is clean and the second emits one finding, when the gate runs, then both are invoked in order and the finding survives aggregation. [unit]
- Given a ShellCheck stub that never exits, when the gate runs, then the gate terminates before the test timeout and emits `refuse` plus `unscannable-timeout` naming the file. [unit]
- Given a shell file of 524,289 bytes, when the gate runs, then ShellCheck is not invoked for it and the receipt refuses with `unscannable-size`. [unit]
- Given a shell file of 524,288 bytes, when the gate runs with a completing stub, then it is scanned rather than size-refused. [unit]
- Given neither `timeout` nor `gtimeout` on PATH, when a shell input is present, then the gate refuses before scanning rather than invoking ShellCheck unbounded. [unit]
- Given `timeout` absent but a working `gtimeout` on PATH, when a shell input is present, then the gate uses `gtimeout` and records the same bounded receipt contract. [unit]
- Given a shell filename beginning with `-`, when the gate invokes ShellCheck, then the `--` separator prevents option injection and the file is still scanned or explicitly refused. [unit]
- Given the real split tree, when the argv-bearer driver starts, then its structural preamble proves the source list exactly equals the tracked fragment glob in order. [integration]
- Given one deleted source statement, one extra unsourced fragment, one reorder, and one conditional source mutation, when each mutant is evaluated in a scratch copy, then the driver structural preamble is RED. [unit]

### Regression Tests

- Given the post-split argv-bearer suite, when run normally, then it prints the same measured row count as before the split and exits green. [integration]
- Given the scan gate handed the driver and all fragments, when ShellCheck is bounded, then the gate returns a receipt rather than hanging. [integration]
- Given a mixed range of one source file and one shell file, when both scanners complete, then engine remains `mixed` and Semgrep coverage checks are unchanged. [unit]

### Edge Cases

- Given malformed JSON from a completed ShellCheck process, when the parser reads it, then the gate refuses rather than treating it as zero findings. [unit]
- Given ShellCheck rc=1 with findings, when the process completed, then findings are reported but do not stop review. [unit]
- Given a deleted input path in the review range, when classification runs, then it is ignored exactly as before and does not count as unscannable. [unit]
- Given a fragment executed directly, when a user or CI invokes it, then its header makes clear it is unsupported; runtime behavior is not part of the contract. [unit]

### Integration Verification

No external service verification. Local deterministic commands only:

- `bash plugins/soleur/skills/review/test/review-scan-gate.test.sh`
- `bash tests/scripts/test-argv-bearer-sweep.sh`
- bounded ShellCheck loop over driver/fragments, exact command to be recorded in implementation evidence.

## Success Metrics

- Scan gate emits a receipt for every hermetic pathological-input case in less than 45 seconds per input.
- Driver plus ten fragments all complete ShellCheck within the bounded probe.
- Post-split suite row count equals the pre-split measured count, currently 832 rows.
- No review pipeline stall is possible from one shell input without a `refuse` receipt.

## Dependencies & Prerequisites

- GNU/coreutils `timeout` or `gtimeout` on hosts running review.
- ShellCheck 0.11.0 locally at planning time; the contract is scanner-version agnostic.
- No network, vendor credential, production host, or Terraform apply is required.

## Risk Analysis & Mitigation

| Risk | Mitigation |
|---|---|
| Extraction reorders or drops assertions | Mechanical contiguous extraction, structural set/order suite, exact row-count floor, normalization-aware comparison to pre-split `HEAD`. |
| ShellCheck emits hundreds of pre-existing style findings once fragments become parseable | Scope completion first; disclose findings. Do not rewrite assertions merely to silence style noise. If review finds the noise blocks evidence quality, a separate severity decision can be reviewed without weakening timeout semantics. |
| Per-file execution is slower for many small files | Files are usually small and ShellCheck startup cost is bounded; correctness/evidence outweighs batching. Measure in scan-gate suite and record duration. |
| `timeout` unavailable on macOS | Resolve `gtimeout`; refuse closed if neither exists rather than scanning unbounded. |
| Split updates security baselines incorrectly | Update only keys whose content moved; run the owning census suites. |
| Foreign full-test battery contention | The foreign processes observed in the first pass have exited; re-check before implementation and rely on focused suites plus CI if new contention appears. |
| Upstream movement invalidates line-number extraction or secondary-file hunks | Rebase before implementation, re-measure the boundary text, and treat the line ranges as extraction coordinates rather than immutable anchors. |
| The provisional 512 KiB prefilter refuses a large file that would have completed (`scripts/test-all.sh` measured 10.43s) | Record the tradeoff visibly in the receipt; do not silently lower scan coverage. The threshold remains pending/assumed pending CTO availability, with timeout as the semantic protection. |

## Resource Requirements

One engineering implementation pass; no infrastructure cost, vendor account, production mutation, or operator-only authorization. Estimated implementation effort is medium because the extraction is mechanical but the verification surface is large.

## Future Considerations

- If ShellCheck warning volume makes review receipts unreadable, evaluate severity policy as a separate ADR-backed decision; this plan deliberately does not weaken the existing scanner semantics.
- If timeout refusals prove too disruptive on large but valid files, evaluate a explicitly disclosed reduced-analysis fallback (`--extended-analysis=false` plus a receipt field such as `analysis=reduced`) as a separate CTO-ruled design. Do not introduce it silently.
- The scan gate's ambient `.shellcheckrc` behavior is unchanged. If deterministic scanner configuration becomes a requirement, evaluate `--norc` or a repo-owned rcfile in a separate evidence-contract change.
- If more suites grow past ShellCheck-practical size, generalize the fragment pattern only after this implementation proves safe.
- The relative-path scan-gate defect remains tracked separately in #12779 and is not folded into this PR.

## Documentation Plan

- Amend ADR-324.
- Update review-skill and receipt-consumer agent prose.
- Preserve the argv-bearer floor-history comment.
- No user-facing documentation or roadmap update.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed (sequential inline fallback)
**Assessment:** This is technical-debt remediation in verification machinery plus a fail-closed scanner contract. The main risks are evidence-contract drift, extraction-order defects, and false confidence from a scan that omits inputs. The CTO/domain assessment recommends ordered sourcing over independent suites, fail-closed `refuse` for any unscanned input, and an ADR-324 amendment because receipt semantics are architectural evidence, not implementation trivia. Complexity: medium. No capability gaps identified.

No cross-domain user-facing, legal, finance, sales, support, operations, or marketing implications detected. Product/UX tier: NONE — no user-facing UI surface or product flow.

## SpecFlow Analysis

Sequential inline fallback of `soleur:product:spec-flow-analyzer`: the critical flows are (a) clean shell input → per-file scan → findings aggregation → `ok`; (b) hanging input → timeout → evidence row → `refuse`; (c) oversize input → no scanner invocation → evidence row → `refuse`; (d) missing timeout binary → immediate `refuse`; (e) tracked fragment added but unsourced → structural RED; (f) all fragments present in order → one shared process → exact floor → green. Edge cases covered in Test Scenarios include malformed JSON, deleted paths, rc=1 findings, mixed source/shell scans, and boundary size equality. No dead-end state may produce `ok` with `unscannable>0`.

## Scoped Advisor Consult

Sequential inline fallback, curated review of the riskiest design: the highest-leverage guidance is to treat scan coverage as a security-evidence invariant rather than an availability convenience. Therefore unscannable inputs must never be downgraded to warning-only `ok`, and the split must be verified structurally rather than by row count alone. The second highest-leverage guidance is to avoid fixing ShellCheck style noise in the same diff; extraction fidelity and bounded completion are the reviewable units.

## References & Research

### Internal References

- Scan gate: `plugins/soleur/skills/review/scripts/review-scan-gate.sh`
- Scan contract tests: `plugins/soleur/skills/review/test/review-scan-gate.test.sh`
- Review skill scan contract: `plugins/soleur/skills/review/SKILL.md`
- ADR-324: `knowledge-base/engineering/architecture/decisions/ADR-324-review-scan-evidence-is-the-orchestrator-read.md`
- ADR-150: `knowledge-base/engineering/architecture/decisions/ADR-150-extract-cutover-inngest-run-body-to-script.md`
- Argv-bearer suite: `tests/scripts/test-argv-bearer-sweep.sh`
- Runner registration: `scripts/test-all.sh` (`tests/scripts/argv-bearer-sweep`)

### External References

- Local GNU `timeout --help` output (verified 2026-11-27): duration, kill-after, signal behavior.
- Local `shellcheck --help` output (verified 2026-11-27 and 2026-11-28): `-f json`, extended analysis, severity flags.
- [koalaman/shellcheck#3177](https://github.com/koalaman/shellcheck/issues/3177) — upstream confirmation that whole-program dataflow analysis drives the memory blow-up and that `--extended-analysis=false` disables checks depending on it.

### Related Work

- Issues: #13098, #13099, #9294, #12779, #7942
- PR: #13006 (the pipeline where the wedge surfaced; still open at planning time)
