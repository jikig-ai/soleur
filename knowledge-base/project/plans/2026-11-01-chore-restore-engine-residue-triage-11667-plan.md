---
title: "chore(registry): engine-edit + battery-armed polish after restore exit-1 tracker (#10932 residue)"
date: 2026-11-01
slug: restore-engine-residue-triage-11667
branch: feat-one-shot-11667-restore-residue-triage
issue: 11667
type: chore
priority: p3
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

## Enhancement Summary

**Deepened on:** 2026-11-01
**Sections enhanced:** Phase 1, Phase 3, Verification protocol, Guard Contract, Acceptance Criteria, held 2b table
**Research agents used:** `soleur:engineering:cto` (binding rulings), learnings-researcher, `soleur:engineering:review:test-design-reviewer`, `soleur:engineering:review:code-simplicity-reviewer`; mechanical halts 4.6, 4.7, 4.8, 4.11, 4.12 run inline (all pass); 4.9, 4.10, 4.13 and 4.55 not triggered.

### Key improvements
1. rc-6 rows now assert the site-specific message and the absence of stub-exit artifacts, so a missing fixture key cannot pass as exit 6.
2. The guard's other half ("only a measured absence exits 4") now has counterpart rows and battery rows E49 to E52; floors become `MIN_ASSERTIONS` 106 and battery 78 (both edit sites).
3. Fixture strings avoid 500 and 429 text so the filed NETWORK-widening deferral cannot silently redden them.
4. Launch line exports `LOG` and `RC`; the Monitor loop carries a deadline and liveness check; the rc file's non-0/1/2 values read as no verdict.
5. Held 2b: R7 marked optional; net -88 bytes with R7 and -126 without.

### Not applied, with reason
- Collapsing the subject census and Observability block: they implement the brief's "grep the claim's SUBJECT" lesson and the plan Phase 2.9 gate; kept.
- Dropping the NETWORK-widening deferral issue: the CTO ruled it a tracked deferral.
- Simplicity reviewer's R2 byte count of -71: re-measured as `len(text.encode())` on the exact anchor, -73.
- Deepen scope note: the third page of `plan-sharp-edges.md` was keyword-scanned (battery, mutation, runbook, exit code, byte) rather than read in full; pages 1 and 2 were read.

## Overview

Tracker #11667 holds the residue left after PR #11787 (merge commit e0af599081) corrected the exit-3 and exit-4 arm wording of the post-destroy restore job `registry_store_restore`. This plan triages that residue into what ships now and what stays held.

Ships now, in one PR (the engine edit arms the roughly 860 s registry mutation battery either way, so the wording edits that also sit in battery paths ride along instead of paying the battery twice):

- **2a, engine.** Four `*)` arms in `scripts/registry-restore-from-ghcr.sh` send an unclassified crane fault to exit 4 ("verification failed, NOT retryable") where the engine's own contract says exit 6 ("could not classify"). Route them to exit 6; a measured absence stays exit 4. CTO ruled option A (below).
- **2c, runbook.** Reword the exit-5 row so it no longer contradicts the measure-first section that tells the operator to re-run; define the partial store after exit 6; document the 7-day `registry-restore-pins` artifact dependency.
- **2d, wording.** `scripts/registry-pull-path-health.sh` "did not accept the write", and an ADR-169 dated amendment for the exit-3 retry rationale and the "wider set" claim.

Held, not in this PR (**2b**): every string in `.github/workflows/apply-web-platform-infra.yml`. The standing workflow-edit constraint applies: an edit fires a production push apply run, which is an operator-only authorization. The exact anchors and net-negative replacements are recorded under "Held: 2b" so the operator can lift the constraint later.

Tracker #11667 stays OPEN throughout. Nothing in this plan closes it; the operator closes it when the residue is resolved or waived. The PR body uses `Ref #11667` and a plain `Ref #9757` (the argv-bearer sweep issue), and no closing keyword.

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality on this branch | Plan response |
|---|---|---|
| `apply-web-platform-infra.yml` is 489,192 of 490,000 bytes | `wc -c` = **488,896** (PR #11785, `32b7ee7d78`, removed bytes after #11787). Headroom is 1,104, not 808. | Held section quotes 488,896 and requires a fresh `wc -c` at lift time. |
| Workflow lines "near 3494, 3496, 3592, 3643, 3475" | Drifted: the strings now sit at 3490, 3492, 3588, 3639, 3471. | Every location is cited by a content anchor (the quoted string), not a line number (`cq-cite-content-anchor-not-line-number`). |
| Engine lines "near 699, 857, 865, 879" | Confirmed exact (`*) die 4` arms). Sibling sites 684, 669, 560 already use `*) die 6`. | Mirror the 683/684 shape. |
| "There is no registry-luks-recut.yml" | Confirmed; the recut is the dispatch-only job `registry_luks_recut` in `apply-web-platform-infra.yml`. | No new workflow file anywhere. |
| ADR-169 wording on exit-3 retry "differs from the engine header" | True for the sentence at "a bounded exit-3 retry that does not conflate it with tunnel convergence". The "non-retryable exit 5 naming rotation" claims were **already amended** on 2026-10-23 (#9757 item 2). | New amendment points at the 2026-10-23 one and adds only the exit-3 rationale and the "wider set" claim. |
| "7-day restore-pins artifact retention" | Confirmed: `retention-days: 7` on the `registry-restore-pins` upload in the recut job. | Runbook documents it; the retention itself is a workflow edit and is held. |
| Recut has been exercised | No `registry_luks_recut` job has run (not skipped) in the last 60 dispatches; no D10 rehearsal log exists. | Nothing here can be validated against a live recut; verification is the suites plus the battery. |
| Collision pre-check | PR #11813 is this branch's own draft (no files). Foreign `test-all.sh` processes belong to the `feat-one-shot-11648-fast-tier-demotion` worktree. | No duplicate work. The foreign runs compete for CPU with the battery; see Verification. |

## Research Insights

### Premise Validation

Checked: #11667 is OPEN; #9757 is CLOSED (plain `Ref` only); PR #11787 merged as e0af599081; both tracker comments read and match the brief; the four engine sites exist exactly as cited; `registry-luks-recut.yml` does not exist; `retention-days: 7` exists. Stale: the byte count and all workflow line numbers (above). `soleur:engineering:cto` verified 488,896 independently.

### Property List

1. Exit 4 from the restore engine means only a measured absence or mismatch; an unclassified read fault exits 6 (the contract's "could not classify").
2. A "NOT retryable" label never contradicts another sentence in the same corpus that tells the operator to re-run (labels are policy, not determinism).
3. The runbook states what holds for a partial store after every non-zero exit, including 6, and names the 7-day artifact dependency of re-run recovery.
4. The A2 rehearsal arm for exit 3 and ADR-169 describe exit 3 the way the engine header does (a failed write **or read** against the sink; retried because a host replace can outrun tunnel re-convergence).
5. The workflow strings stay consistent with 1 to 4 once the constraint is lifted (held).

### Cut List

| Mechanism considered | Property | Disposition |
|---|---|---|
| New exit code for "transient read fault" | 1 | Cut. Exit 6 already means "could not classify"; the W9 wiring suite compares header codes to emit sites and arms, so a new code ripples into the workflow. |
| Widen `classify()` NETWORK to 500 or 429 | 1 | Cut for this PR (CTO): it changes which failures the job auto-retries on the destroy path, a separate decision. Tracked as a deferral. |
| Job-level retry on exit 6 | 1 | Cut. Workflow edit; and CTO ruled the job does not retry 6, so the operator re-dispatches after reading the stderr. |
| Change `retention-days` | 3 | Cut. Workflow edit; documented only, deferral issue filed. |
| Narrow the exit-4 "NOT retryable" label (option B) | 1, 2 | Cut. After A every remaining exit 4 is a genuine absence or mismatch, so the label is true. |
| C4 edit to the restore edge ("resumable, so a partial pass is recovered by re-running") | 2 | Cut. Narrowly true (the engine is resumable) and the CTO ruled no C4 touch; listed in the subject census so it is a decision, not an oversight. |
| New lint that pins "NOT retryable" wording | 2 | Cut. The subject census below plus W9 already cover it; a wording lint is a new guard to maintain. |

### Institutional learnings applied

- `knowledge-base/project/learnings/2026-11-01-not-retryable-is-a-label-not-a-determinism-claim.md`: quote the engine header's label, not the consequence inferred from it; deleting a "re-run" orphans sentences that depended on it; grep the claim's SUBJECT.
- `knowledge-base/project/learnings/2026-09-22-my-sweep-was-keyed-on-a-literal-and-the-claim-had-another-spelling.md`: index the sweep by the proposition (see the census).
- `knowledge-base/project/learnings/2026-09-14-the-sweep-that-retired-false-sentences-wrote-new-ones-from-my-own-issue-comment.md`: re-derive each inherited sentence from the code, not from the tracker comment. Applied below: the tracker's claim "re-run recovery" was re-read against the download step.
- `knowledge-base/project/learnings/workflow-issues/2026-10-30-cd-setsid-backgrounding-launched-suites-on-wrong-tree.md` and `2026-10-29-a-timed-out-call-skipped-the-launch-line-behind-it-and-i-reported-the-gate-running.md`: one detached launch per call, explicit `cd`, confirm the process exists and its cwd.
- `knowledge-base/project/learnings/2026-08-19-my-battery-reverted-the-fix-it-was-testing.md`: commit the verified unit before the battery runs; the battery restores from a `cp` pristine copy, never `git checkout`.
- `knowledge-base/project/learnings/2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md`: every new emitter arm gets its own battery row (four arms, four rows).
- `knowledge-base/project/learnings/2026-09-19-a-sibling-merge-took-the-apply-workflow-over-githubs-byte-limit-and-nothing-in-repo-said-so.md`: the 490,000-byte limit; measure deltas against the merge base.

### Feasibility probe (done at plan time, scratch copy only)

A copy of the engine with the four-site edit applied, run against an unmodified copy of `tests/scripts/test-registry-restore-from-ghcr.sh` in the session scratchpad, finished **99 passed, 0 failed**. So (a) no existing assertion relied on unclassified-to-4 at those sites, and (b) the existing suite cannot see the change, which is why new RED rows and battery rows are required rather than optional. The worktree was not modified.

### Subject census (grep the claim, not the phrasing)

Subject 1, "exit 4 means untrustworthy and not retryable" (engine header row 4; `die 4` sites; runbook row 4 and the ENGINE-CAPABILITY note; workflow exit-4 arm [held]; pull-path-health exit-4 arm; `registry-breakglass-mirror` SKILL exit table). After A, true everywhere except that the registry-breakglass-mirror SKILL documents the **mirror script's own** codes, which this PR does not audit (Non-Goal).

Subject 2, "a partial pass is recovered by re-running" (workflow job summary near "recovered by re-running" [held]; workflow comment above the restore job `timeout-minutes` [comment, left]; runbook "If the restore job fails" paragraph [edited]; runbook line "the engine is resumable and the job itself retries only exit 3" [edited]; `apply-web-platform-infra-job-rationale.md` section on exit 1 ("seven-day retention") [reviewed, accurate]; ADR-169 Consequences bullet on `ci-deploy.sh` rollback ("wider set") [amended]; `model.c4` restore edge "resumable, so a partial pass is recovered by re-running" [reviewed, left, Cut List]).

Subject 3, "exit 5 is not retryable" (engine header row 5 and the `die 5` message at the copy site "retrying will not clear it"; runbook rows/sections at lines citing "non-retryable exit `5`", "exits 1, 4 and 5 are not retryable" twice, and the measure-first table; ADR-169 [already amended 2026-10-23]; workflow exit-5 arm [held]; pull-path-health exit-5 arm [reviewed]).

Subject 4, "the sink did not accept the write" (engine header row 3 "accept or serve the write"; pull-path-health A2 exit-3 arm; runbook row 3 already says "accept or serve a request"; workflow exit-3 arm already says "accept or serve a request").

Subject 5, "the store is EMPTY" (workflow only: four strings [held]; runbook describes the window and is accurate; `registry_store_restore` summary "empty or partial" [reviewed, accurate]).

Subject 6, "a wider set" (workflow summary [held]; runbook "The restore job has no wider-set input" [accurate]; ADR-169 Consequences "Recoverable by re-running the restore with a wider set" [amended]).

## Technical Rulings (summary)

Full rows are in `knowledge-base/project/specs/feat-one-shot-11667-restore-residue-triage/decision-challenges.md`.

- Ruled by CTO agent, 2026-11-01: **Option A.** At each of the four sites add an explicit `NOTFOUND|BLOBMISSING) die 4` arm keeping today's message and make `*) die 6`. CONTENTMISMATCH and LAYERFORMAT fall to 6 at these HEAD-read sites. No NETWORK widening. The exit-4 label stays as is. Add "re-run is safe and resumable; the job does not retry 6, so re-dispatch by hand after reading the crane stderr" to the header's exit-6 line and runbook row 6.
- Ruled by CTO agent, 2026-11-01: row 5 reads "not retryable as-is: the job does not retry it, and re-running unchanged burns the window; re-run only after the measure-first section's `htpasswd_push_matches` reading says to". Apply the same "unchanged" qualifier to the engine header's exit-5 row. The measure-first section stays.
- Ruled by CTO agent, 2026-11-01: a partial store after exit 6 is recovered by re-running (crane skips blobs the sink already holds); read the crane stderr first; the store stays unverified until a pass ends in exit 0.
- Ruled by CTO agent, 2026-11-01: retention is documented in the runbook only, plus a deferral issue with a re-evaluation criterion (`wg-when-deferring-a-capability-create-a`). The expiry recovery step must not be invented (see Phase 4).
- Ruled by CTO agent, 2026-11-01: ADR-169 gets a dated `## Amendment 2026-11-01`; no body rewrite, no new ADR, no C4 change. Pull-path-health and engine edits batch into one PR.
- Ruled by CTO agent, 2026-11-01: four new battery rows, one per site; local fast suites run directly; the battery launches once, detached; only the rc file can say passed.

## Held: 2b (workflow strings) — operator-gated, NOT in this PR

**Why held.** Operator-only class: scope and production-mutating authorization. A merge touching `.github/workflows/apply-web-platform-infra.yml` fires a push-triggered apply run against production infrastructure. The standing constraint forbids the edit; the plan therefore contains **no edit to that file** and `git diff --stat origin/main` must show it untouched (AC1).

**Lift conditions (all required):** (1) the operator lifts the constraint in writing; (2) `soleur:engineering:cto` rules on the final wording; (3) an apply-trigger plan states what the merge-triggered apply will do (the tracker's verification note for #11787 is the template: preflight and apply green, restore job skipped on push, `wc -c`, health, alert-channel sweep); (4) one PR only; (5) net-negative bytes measured against the merge base with a fresh `wc -c` (488,896 at plan time, limit 490,000); (6) the `tests/scripts/test-registry-d10-workflow-wiring.sh` W9 suite stays green (it runs the restore step's real body and the summary step, so wording that drops an exit-code name or the summary contract reddens it).

Locations are content anchors (current line in parentheses, for orientation only). Replacements were byte-measured at plan time on a scratch string; re-measure at lift time.

| # | Anchor (exact current text) | Problem | Proposed replacement | Bytes |
|---|---|---|---|---|
| R1 | `echo "### The store is EMPTY — the chained restore runs next"` (about 3471) | Read after the restore ran, the heading is stale | `### The store was rebuilt empty — the chained restore runs next` | +9 |
| R2 | `If the restore job fails, re-run it: the restore engine is resumable, so a partial pass is recovered by re-running rather than by repairing state. Its per-exit-code \`::error::\` maps to one operator action each in the runbook.` (about 3490) | Contradicts the not-retryable exits 1, 4, 5 | `If the restore job fails, follow the runbook row for its exit code: re-running is safe (the engine is resumable) but only some exits can be cleared by it.` | -73 |
| R3 | `…no older image in the store to roll back to; re-run the restore with a wider set if you need one._` (about 3492) | Names a re-run with no input to widen the set | `…no older image in the store to roll back to._` (drop the clause) | -53 |
| R4 | `The store is EMPTY and this job cannot refill it. Fix the credential and re-run this job — the restore engine is resumable.` (about 3588) | A re-run can start from a partly refilled store | `The store is EMPTY or only partly refilled. Fix the credential, then re-run this job.` | -40 |
| R5 | `so this attempt wrote nothing and the store is still EMPTY.` on the exit-78 arm (about 3639) | A statement about the attempt, not the store; the exit-1 arm already says it right | `so this attempt wrote nothing and the store is unchanged by this step.` | +11 |
| R6 | exit-4 arm ends `NOT retryable: read the per-entry lines above.` (about 3634) | No runbook pointer | `NOT retryable: read the per-entry lines above, then runbook row 4.` | +20 |
| R7 (optional) | exit-3 arm ends `Verify the registry host is serving, then re-run this job.` (about 3633) | A partly refilled store is not a verified one | append ` Do not deploy until a re-run exits 0.` | +38 |

Net at plan time: **-88 bytes** with R7, **-126 bytes** without it (488,896 to 488,808 or 488,770); each figure is `len(text.encode())` on the exact anchor text, which occurs once in the file. R7 is optional because it adds new behavior, not a correction. Two summary lines are reviewed and intentionally left: the `cancelled` line ("Re-run this job — the engine is resumable") is accurate for a cancellation, and the `failed` line ("empty or partial") is accurate. The exit-5 arm's "retrying will not clear it" should gain the same "unchanged" qualifier as the runbook when the file is next opened. The job-rationale runbook section on exit 1 needs no change.

## Implementation Phases

Order follows `cq-write-failing-tests-before`: fixtures first (RED), then the engine (GREEN), then rows that prove the fixtures bite.

### Phase 1: RED fixtures in the engine suite

File: `tests/scripts/test-registry-restore-from-ghcr.sh`. Add rows beside the existing exit-4 rows (the `fx-sigmissing` and `fx-sigsrc` block) and the exit-6 row, using the suite's `ok_fixtures` + `fixture` helpers. Fixture keys already exist in `ok_fixtures`.

| Site | Fixture key to override (rc 1, empty stdout, stderr unrecognised) | Expected |
|---|---|---|
| read-back of the copied image | `${TARGET}/${WP}:v0.249.4` | rc 6, message names the read-back |
| GHCR-side signature digest read | `ghcr.io/${WP}:sha256-${D1#sha256:}` | rc 6 |
| signature copy | `copy:${TARGET}/${WP}:sha256-${D1#sha256:}` | rc 6 |
| sink-side signature read-back | copy rc 0, then `${TARGET}/${WP}:sha256-${D1#sha256:}` rc 1 | rc 6 |

Stderr strings: use shapes that are neither in `classify()` nor plausible widening candidates (the suite's existing `Error: something nobody has seen before`, and a second such as `Error: unexpected response shape from sink`). Do **not** use HTTP 500 or 429 text: those are the strings the NETWORK-widening deferral would reclassify to exit 3, which would redden these rows for an unrelated reason.

**Each rc-6 row must pass for the right reason** (a missing fixture key makes the stub exit 70 and any unmodelled call shape exits 64 with a `stub:` message; both reach `classify` as UNKNOWN and would otherwise also yield 6). So every new row asserts all of: rc 6; the site-specific phrase of the new `die 6` message; the output contains neither `NO FIXTURE` nor `stub:`; and the calls file shows the site's own argv as the final crane call.

**Counterpart rows (rc 4), because the guard's other half is "only a measured absence exits 4".** Existing rows cover MANIFEST_UNKNOWN at sites 2 and 4 only. Add: MANIFEST_UNKNOWN at site 1 (image read-back) and at site 3 (signature copy), plus one `BLOB_UNKNOWN: blob unknown to registry` row at site 3 (BLOBMISSING is untested at every site today). Seven new assertions in all (four rc-6, three rc-4).

Raise `MIN_ASSERTIONS` in the same file from 99 to 106 (it sits at the engine suite's anti-vacuity floor, equal to today's count). Run the suite now: the four new rc-6 rows must FAIL (rc 4, not 6); the three counterpart rows and the other 99 pass. Record that run per row; it, not the battery's `caught` lines, is the proof each row bites.

### Phase 2: engine edit (GREEN)

File: `scripts/registry-restore-from-ghcr.sh`.

1. At each site (anchors: `could not read ${dst} back after copying it`, `no cosign signature (${sig_tag}) found at GHCR`, `the signature ${sig_tag} could not be copied for ${repo}`, `is not readable back from the sink, so`), replace the `*)  die 4 "…"` arm with `NOTFOUND|BLOBMISSING) die 4 "…"` (message unchanged) followed by `*) die 6 "could not classify …. crane: ${err}"`. The new exit-6 messages each begin with a distinct phrase naming the site (battery anchors depend on uniqueness) and must not contain a single quote (the battery quotes anchors in bash).
2. **Do not touch** the existing battery-anchored lines: `if [[ -z "$dst_digest" ]]; then` (E05), `if [[ -z "$(digest_of "$WORK/sigsrc.out")" ]]; then` (E11), the `sigdst.out` emptiness line (E12), the signature `crane_capture … copy` line (E13). The battery pre-flight resolves anchors uniquely and a moved line fails with no verdict.
3. Header edits, row formats unchanged (`restore_header_codes` reads `#   N  LABEL`): exit 5 row gains the "unchanged" qualifier ("retrying unchanged only wastes the window; re-run only after the measure-first reading"); exit 6 row gains "re-run is safe and resumable; the job does not retry 6, so re-dispatch by hand after reading the crane stderr"; exit 4 row keeps "NOT retryable" unchanged (CTO: after A the label is true as written). The `die 5` copy-site message "retrying will not clear it" becomes "retrying unchanged will not clear it".
4. No new exit code, no `classify()` change (Cut List). `restore_emit_codes` (in `tests/scripts/lib/restore-engine-header.sh`, consumed by the W9 wiring suite) must still yield `1 2 3 4 5 6 78`.

Re-run the engine suite: 106 assertions green.

### Phase 3: battery rows

File: `tests/scripts/test-registry-gate-mutation-battery.sh`. After E44 add eight rows, each through `mutate "<label>" engine '<old>' '<new>'` (the engine suite must go RED): **E45 to E48**, one per site, revert the new `*) die 6` to `die 4`; **E49 to E52**, one per site, change the `NOTFOUND|BLOBMISSING) die 4` arm to `die 6` (a mutant that loses the absence arm survives E45 to E48 otherwise). Anchors are the unique message prefix on the full line (check against line 560, 669 and 684 prefixes). The replacement keeps the same prefix so `old != new` holds. Raise the anti-vacuity floor from 70 to 78 at **both** edit sites (the `dispatched < 70` comparison and the "floor is 70" message text). Record the added runtime (estimate only: the engine suite takes about 12 s per invocation, so about 100 s for eight rows on top of roughly 860 s; replace with the measured figure from the green run). Read the battery's `pre-flight: 78/78 anchors resolve uniquely` line first; it is the instrument control.

### Phase 4: runbook (2c)

File: `knowledge-base/engineering/operations/runbooks/registry-luks-recut-6929.md`, edits by content anchor.

1. Row 5 of the restore exit-code table: apply the CTO wording. Also the two sentences "exits 1, 4 and 5 are not retryable" (in the failure-mode bullet and in "If the restore job fails"): add "as-is" for 5 and point at the measure-first section.
2. Row 6: add the "re-run is safe and resumable; the job does not retry 6; re-dispatch by hand after reading the crane stderr" sentence. Remove nothing else (the 2026-08-09 history stays).
3. Row 4: one clause that exit 4 now means a measured absence or mismatch and an unclassified read fault exits 6; keep "NOT retryable".
4. "If the restore job fails": add the partial-after-exit-6 sentence (CTO ruling) and the artifact dependency: re-run recovery holds only while the `registry-restore-pins` artifact exists (`retention-days: 7`, set on the recut job's upload); retention is held with the workflow file; link the deferral issue. **Do not invent the expiry procedure.** What the plan verified statically: the restore job's download step (`actions/download-artifact`, name `registry-restore-pins`) has no `continue-on-error`, so after expiry a re-run is expected to fail at the download step before any engine call. State exactly that as unmeasured, and that the only documented route is a new `registry-luks-recut` dispatch, which the rationale runbook already calls unmeasured for this failure.
5. Subject-grep the runbook again after editing (census subjects 1, 2, 3) and fix any sentence the edit orphaned.

### Phase 5: pull-path-health and ADR-169 (2d)

1. `scripts/registry-pull-path-health.sh`, the A2 exit-3 arm: "did not accept the write" becomes "did not accept or serve a request". Wording only. `grep` showed no test pins the old string; re-check before editing. Because `registry-pull-path-health.sh` is `SUT_GATE` in `REGISTRY_BATTERY_PATHS`, this also arms the battery (already armed by the engine).
2. ADR-169: append `## Amendment 2026-11-01 — exit-3 retry rationale and the "wider set" claim (#11667)` after the 2026-10-23 amendment. Content: exit 3 is retried because a host replace can outrun the Cloudflare Tunnel's re-convergence onto the replaced origin (engine header), correcting the sentence that says the retry "does not conflate it with tunnel convergence"; the Consequences line "Recoverable by re-running the restore with a wider set" is wrong because the restore job has no wider-set input (the restore carries the required pin set only; a wider set is a separate change); "non-retryable exit 5" is a policy label, already corrected by the 2026-10-23 amendment, which this one points at; unclassified read faults now exit 6, not 4. Decision unchanged. Use the `soleur:architecture` skill conventions; do not edit the body.

### Phase 6: verification

See "Verification protocol" and the Acceptance Criteria.

### Phase 7: ship hygiene

PR body: `Ref #11667` and a plain `Ref #9757`; no closing keyword anywhere, including negated forms. Do not touch #11312 or #10924, or `scripts/inngest-gate-witness-classify.sh` and its test. File the two deferral issues (below) before marking the PR ready. Post-merge: leave #11667 open and say in the tracker comment that 2a, 2c and 2d are done and 2b is held; the operator decides the rest.

## Verification protocol (battery-armed)

1. Fast suites, run directly and in the foreground: `bash tests/scripts/test-registry-restore-from-ghcr.sh`, `bash tests/scripts/test-registry-pull-path-health.sh`, `bash tests/scripts/test-registry-d10-workflow-wiring.sh`. Read each `=== N passed, M failed ===` line.
2. Commit the verified unit first (the battery restores from a pristine copy, but the learning is to never mutate over uncommitted work).
3. Launch the battery, detached, **in its own Bash call** with an explicit `cd` and absolute paths: `cd <worktree> && export LOG=<scratch>/battery.log RC=<scratch>/battery.rc && setsid -n bash -c 'bash tests/scripts/test-registry-gate-mutation-battery.sh >"$LOG" 2>&1; echo $? >"$RC"' </dev/null >/dev/null 2>&1 &` (both variables exported in that same call, because the single-quoted body expands them in the child shell; unset they give an ambiguous redirect and no rc file is ever written) with `LOG` and `RC` in the session scratchpad. In a separate call confirm the process exists and its cwd is the worktree (`/proc/<pid>/cwd`). Poll the rc file with the Monitor tool: an until-loop with a deadline and a liveness check on the pid, failing loudly when either trips, never a foreground sleep.
4. Read the rc file. Only `0` is "passed". `1` is a surviving mutation (fix the suite or the guard), `2` is a harness fault with no verdict, and any other value (a kill, 137) is also no verdict. If the rc file is `6`, absent, or the run is queued, **the required `test` CI context is the gate**; never describe a local run as passed from anything but the rc file.
5. Foreign `test-all.sh` processes from another worktree may be running; the battery's per-suite `timeout 300` still applies. A timeout reads as CAUGHT (non-zero), so a slow machine can mask a survivor: read the per-mutation `caught` lines, not just the rc, and use the Phase 1 per-row RED record as the evidence that each row bites.
6. Open the PR as a draft, let queued CI run, and merge only on the required `test` context (and the other required checks). `wg-ship-push-before-merge` applies.

## Files to Edit

- `scripts/registry-restore-from-ghcr.sh`: four `*)` arms to `NOTFOUND|BLOBMISSING` (4) plus `*)` (6); header rows 4, 5, 6; the copy-site `die 5` message.
- `tests/scripts/test-registry-restore-from-ghcr.sh`: four RED rows, three counterpart rows and `MIN_ASSERTIONS` 99 to 106 (Phase 1).
- `tests/scripts/test-registry-gate-mutation-battery.sh`: rows E45 to E52 and the floor 70 to 78 (two edit sites).
- `scripts/registry-pull-path-health.sh`: one A2 exit-3 arm phrase.
- `knowledge-base/engineering/operations/runbooks/registry-luks-recut-6929.md`: rows 4, 5, 6, two "not retryable" sentences, "If the restore job fails".
- `knowledge-base/engineering/architecture/decisions/ADR-169-what-authorizes-destroying-the-sole-pull-path.md`: dated amendment appended.

Verified paths: each exists on this branch (`git ls-files` on each). Globs: none used.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-11667-restore-residue-triage/decision-challenges.md` and `tasks.md` (planning artifacts).
- No new source file, no new workflow, no new test file.

## Open Code-Review Overlap

None. Queried open `code-review` issues for each file above (`scripts/registry-restore-from-ghcr.sh`, `scripts/registry-pull-path-health.sh`, both test files, the runbook, ADR-169): no body names any of them.

## Not touched, by constraint

`.github/workflows/apply-web-platform-infra.yml` (held 2b); issues #11312 and #10924; `scripts/inngest-gate-witness-classify.sh` and its test (another session; not present in this worktree). `knowledge-base/engineering/architecture/diagrams/*` (no C4 change).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Engine (scripts/registry-restore-from-ghcr.sh near lines 699, 857, 865, 879): unclassified read faults exit 4 where the contract says exit 6. Either route them to exit 6 or narrow the \"NOT retryable\" label." [brief] | Phase 2, Technical Rulings (option A) | mapped |
| 2 | "Engine change arms the ~860 s registry battery." [brief] | Phase 3 and Verification protocol | mapped |
| 3 | "Workflow strings in .github/workflows/apply-web-platform-infra.yml (byte-budgeted, net-negative only)" [brief] | Held: 2b | descoped — justification: the brief's HARD CONSTRAINT forbids any edit to that file; the plan records locations and replacements instead, as the brief requires |
| 4 | "Runbook (…registry-luks-recut-6929.md): the exit-5 conditional re-run (~562) and the 7-day restore-pins artifact retention." [brief] | Phase 4 | mapped |
| 5 | "scripts/registry-pull-path-health.sh ~578 (\"did not accept the write\") and the ADR-169 wording on exit-3 retry." [brief] | Phase 5 | mapped |
| 6 | "When the residue is fully resolved or waived, the operator closes #11667. Never close it." [brief] | Phase 7 (Ref only; tracker left open) | mapped |
| 7 | "the plan must say the lift would require soleur:engineering:cto plus an apply-trigger plan, one PR, net-negative bytes" [brief] | Held: 2b, lift conditions | mapped |
| 8 | "if it changes the engine, the plan must arm the ~860 s battery (launch detached with `setsid -n`, read the rc file, if rc=6 or queued CI's required `test` context is the gate; never call a local run passed)" [brief] | Verification protocol | mapped |
| 9 | "Lessons: \"NOT retryable\" is a policy label, not a deterministic property. … grep the claim's SUBJECT" [brief] | Subject census; Phases 4 and 5 re-grep | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Engine four-site edit | "Either route them to exit 6 or narrow the \"NOT retryable\" label" | asked (CTO chose route) |
| New RED fixtures (Phase 1) | "never call a local run passed" (a green verdict needs a suite that can go red) | inferred — justification: the feasibility probe showed the existing 99 assertions stay green with the change, so without new rows the edit is untested |
| Battery rows E45 to E52 and floor 78 | "Engine change arms the ~860 s registry battery." | inferred — justification: CTO ruling; each arm can be deleted independently and only a row per arm detects it |
| Engine header edits (rows 4, 5, 6) | "narrow the \"NOT retryable\" label" | asked (label wording) |
| Runbook edits | asks 4 | asked |
| `die 5` message qualifier | "grep the claim's SUBJECT, not its phrasing" | asked |
| pull-path-health phrase | asks 5 | asked |
| ADR-169 amendment | asks 5 | asked |
| Deferral issues (retention; NETWORK widening) | "the 7-day restore-pins artifact retention" | inferred — justification: `wg-when-deferring-a-capability-create-a` and the CTO ruling require a tracked deferral for anything documented-only |
| Held 2b table | "list 2b as deferred/held, with exact text locations and proposed net-negative replacements" | asked |

### Split Assessment

- Subsystems touched: 3 — `scripts/` plus `tests/scripts/`, `knowledge-base/engineering/operations/`, `knowledge-base/engineering/architecture/`
- Planned files: 6 edited, 2 planning artifacts | Estimated changed lines: about 250
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR (the battery is armed by the engine edit regardless, so splitting the wording edits out would only add a second 860 s run)

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** `soleur:engineering:cto` ruled on all five forks (route to exit 6, exit-5 wording, partial-after-6, amendment form, battery rows, hold confirmation). Product, legal, finance, marketing, operations, sales and support: none relevant. No UI surface (no `components/`, `app/` or `.tsx` paths), so no Product/UX gate and no wireframe. The production-mutating authorization for 2b is an operator item and is recorded as such in `decision-challenges.md`.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly. This is operator-facing restore tooling on a dispatch-only path that has not run since the store went live LUKS (2026-08-10). The realistic failure is an operator misreading a restore exit code during an empty-store window, delaying the refill of the registry that every host pulls from.
- **If this leaks, the user's workflow is exposed via:** no vector. No credential, token or user data is read or written; the diff changes exit routing between two failing codes and prose.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the change can only re-route an already-failing path from 4 to 6 (both non-zero) and edit documentation, so it cannot turn a failed verification into a pass; the next tier would apply if a fail-open were possible.

threshold: none, reason: the engine edit re-labels failing exits between two non-zero codes on unclassified faults and the rest is documentation, so no path can make an unverified restore read as verified and no user data or credential is touched.

## Observability

```yaml
liveness_signal:
  what: the engine's own `restore_summary target=… result=ok` line plus the registry_store_restore job conclusion on a recut dispatch (per-run; the job has not run since 2026-08-10)
  cadence: per recut dispatch (dispatch-only, no schedule)
  alert_target: the operator who dispatched the run, via the run's failed-job state and the job's per-exit-code ::error:: annotation
  configured_in: .github/workflows/apply-web-platform-infra.yml (registry_store_restore, unchanged here) and scripts/registry-restore-from-ghcr.sh
error_reporting:
  destination: the engine's `::error::registry-restore-from-ghcr:` line in the job log, then the step's `restore FAILED exit N` annotation
  fail_loud: exit 6 now carries unclassified read faults, so the exit-6 annotation ("COULD NOT CLASSIFY … read the crane stderr") fires instead of the exit-4 "contents NOT trustworthy" one
failure_modes:
  - mode: an unclassified read fault is reported as exit 4 (the defect being fixed)
    detection: four new RED rows in the engine suite and battery rows E45 to E52; CI required `test` context
    alert_route: PR check failure before merge
  - mode: a new `*) die 4` arm is added later without a die-6 sibling
    detection: the engine suite's exit-6 rows plus the W9 header-vs-emit-sites comparison (code set only); the per-site rows cover the four known sites
    alert_route: PR check failure before merge
logs:
  where: GitHub Actions run log for the registry_store_restore job (`gh run view <run-id> --log-failed`, no SSH)
  retention: GitHub's default run-log retention
discoverability_test:
  command: grep -c -e 'NOTFOUND.BLOBMISSING) die 4' scripts/registry-restore-from-ghcr.sh
  expected_output: 5
```

## Guard Contract

### Guard 1 — unclassified sink and signature reads exit 6, never 4

**Property.** An unclassified crane failure at any read or copy of the sink's image or signature manifest exits 6, and only a measured absence (NOTFOUND or BLOBMISSING) exits 4.

**Assembly.** The chokepoint is `classify()` consumed through `case "$(classify …)"` / `case "$cls"` blocks. The members are: the image copy (existing `NOTFOUND|BLOBMISSING) 4` / `*) 6`), the image read-back (new), the GHCR signature read (new), the signature copy (new), the sink signature read-back (new), `verify_die` (existing), and source resolution (existing). Members drift, so the enumeration is by grep of every `case` over `classify`, not by this list; there is more than one site, and a guard scoped to one is the defect. The suite rows pin the four edited sites; the battery rows pin that each arm exists independently.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | E45: read-back site `*) die 6` reverted to `die 4` | RED (engine suite) |
| 2 | E46: GHCR-signature-read site reverted to `die 4` | RED |
| 3 | E47: signature-copy site reverted to `die 4` | RED |
| 4 | E48: sink-signature-read-back site reverted to `die 4` | RED |
| 5 | E49 to E52: each site's `NOTFOUND\|BLOBMISSING) die 4` arm changed to `die 6` (a mutant that loses the absence arm) | RED (the counterpart rows expect rc 4) |
| 6 | Own dispatch: delete one of E45 to E52 from the battery | exit 2, harness fault with no verdict, via the raised floor (78); a refusal, not a caught mutation |

Rows 2 to 4 (and the matching E50 to E52) are the second-member rows: each reverts one site while the sites before it stay compliant, so a suite that checked only the first site would let them through. **Named residual (recorded, not claimed):** a fifth `*) die 4` classified site added in a later change is caught by no row here, and the W9 code-set comparison cannot see it either.

**Harness rows.** Edit the suite, not the guard, with a scripted check: (a) swap one new fixture's stderr to `MANIFEST_UNKNOWN` and its rc-6 row must go RED; (b) point one fixture at a nonexistent key and its row must go RED (the stub's exit 70 must not read as an rc-6 pass). Must-PASS non-canonical inputs: the two differently shaped unrecognised strings, the `BLOB_UNKNOWN` row, and the MANIFEST_UNKNOWN rows asserting rc 4.

**Anchor.** The suite and the SUT live in the same commit, so a weakening that edits both passes the suite. What sits outside the commit: the battery runs the engine suite against mutants of the pristine SUT and the floor of 78 is a lower bound; a PR that deletes a row and the matching engine arm together keeps both consistent. The independent anchor is review of the battery diff plus the W9 header-vs-emit-sites code-set comparison. Stated, not solved.

## Architecture Decision (ADR/C4)

Gate evaluated: no new architectural decision. The decision of ADR-169 is unchanged; the amendment is a correction of recorded wording, the same class as the 2026-10-23 amendment. C4 impact: none — checked against the three model files for the actors, systems and relationships this change could touch (the GitHub Actions runner as actor, GHCR and zot as external systems, the restore edge github to zotRegistry): all already modeled; the only affected sentence is the restore-edge description in `model.c4` ("resumable, so a partial pass is recovered by re-running"), which stays narrowly true and is a recorded Cut. The cardinalities embedded in the edge prose (counts) do not move; no `.c4` file is edited, so `c4-count-parity` has nothing to re-run.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `git diff --name-only origin/main...HEAD` lists no `.github/workflows/` path. (Verify: `git diff --name-only origin/main...HEAD | grep -c '^\.github/workflows/'` prints `0`.)
- [ ] AC2: the four sites each have `NOTFOUND|BLOBMISSING) die 4` and a `*) die 6` arm (`scripts/registry-restore-from-ghcr.sh`, Phase 2).
- [ ] AC3: Phase 1 rows were observed RED before the engine edit and are green after; `MIN_ASSERTIONS` is 106, each rc-6 row asserts the site-specific phrase and the absence of `NO FIXTURE` and `stub:`, and `bash tests/scripts/test-registry-restore-from-ghcr.sh` ends `0 failed`.
- [ ] AC4: the discoverability command above prints `5` (the existing copy-site arm plus the four new ones; it prints `1` before the edit; the separate `NOTFOUND)` and `BLOBMISSING)` arms in `verify_die` do not match it), the emitted code set is still `1 2 3 4 5 6 78` (the W9 wiring suite compares header, emit sites and workflow arms and must stay green), and no new exit code exists.
- [ ] AC5: battery rows E45 to E52 exist, the floor is 78 at both edit sites, the pre-flight line reads `78/78 anchors resolve uniquely`, and the battery's rc file reads `0` from a local run, or the required `test` CI context is green with the local run described only as "not completed" (never "passed").
- [ ] AC6: runbook row 5 carries the "not retryable as-is" wording; row 6 carries the "re-run is safe" sentence; "If the restore job fails" states the partial-after-6 rule and the 7-day artifact dependency without an invented expiry procedure; a re-grep of subjects 1 to 3 finds no orphaned sentence.
- [ ] AC7: ADR-169 has a `## Amendment 2026-11-01` section and no other ADR-169 line changed (`git diff -U0` shows additions only).
- [ ] AC8: pull-path-health A2 exit-3 arm reads "did not accept or serve a request".
- [ ] AC9: PR body contains `Ref #11667` and `Ref #9757` and none of the closing keywords (verify with a grep over the body text); #11312, #10924 and the inngest-gate-witness files are not in the diff.
- [ ] AC10: two deferral issues exist (retention; NETWORK widening for 500 and 429), each with a re-evaluation criterion and a milestone from the roadmap, and the runbook links the retention one.

### Post-merge (operator)

- [ ] #11667 remains OPEN. A tracker comment lists 2a, 2c, 2d done and 2b held. No agent closes it.

## Test Scenarios

- Given a sink that returns an unrecognised error on the read-back, when the engine runs, then it exits 6 and prints a "could not classify" line naming the read-back.
- Given a sink that returns MANIFEST_UNKNOWN on the read-back, then it still exits 4.
- Given the same pair for the GHCR signature read, the signature copy, and the sink signature read-back.
- Given a tunnel blip (`dial tcp … no such host`) on any of the four, then it still exits 3 (retryable), unchanged.
- Given the battery with E45 applied (`die 6` back to `die 4`), then the engine suite goes RED.

## Dependencies & Risks

- **Battery cost and masking.** About 860 s plus about 50 s; a per-suite timeout reads as CAUGHT, so read the `caught` lines.
- **Anchor drift.** An engine edit that moves or duplicates an anchored line makes the battery exit 2 with no verdict; Phase 2 forbids touching E05, E11, E12, E13 anchors.
- **Foreign load.** Another worktree is running `test-all.sh`; CI's required `test` context is the authoritative gate.
- **Residual named in the Guard Contract:** a fifth `*) die 4` site added later is not caught mechanically.
- **Unverified:** behavior of a re-run after the 7-day artifact expiry (static reading only; no recut has run).
- **Deferral tracking:** retention change (workflow edit, held) and NETWORK widening for 500 and 429 (changes auto-retry on the destroy path) each need an issue; held 2b itself is tracked by #11667.

## Non-Goals

- Auditing `plugins/soleur/skills/registry-breakglass-mirror/scripts/mirror-ghcr-to-zot.sh` for the same unclassified-to-4 shape; it has its own exit contract.
- Any change to `classify()`, the job-level retry rule, artifact retention, or the workflow.
- Dispatching any workflow.
