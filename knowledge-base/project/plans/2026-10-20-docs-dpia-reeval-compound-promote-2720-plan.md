---
title: "compliance: week-4 DPIA re-evaluation for compound-promote loop (#2720)"
type: docs
date: 2026-10-20
slug: docs-dpia-reeval-compound-promote-2720
branch: worktree-agent-aa1d073f6314c9461
issue: 6107
closes: none
ref: 6107
priority: p3
domain: legal
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# compliance: week-4 DPIA re-evaluation for compound-promote loop (#2720)

Spec lacks valid `lane:` (no `spec.md` for this branch) - defaulted to cross-domain (fail-closed).

## Enhancement Summary

**Deepened on:** 2026-10-20. **Agents/seats used:** `soleur:legal:clo` (plan-time consult), `soleur:product:cpo` (sign-off), `soleur:engineering:cto` (re-arm fork), learnings-researcher, user-impact-reviewer, spec-flow-analyzer, code-simplicity-reviewer; gates 4.6-4.12 run by the planner.

Key improvements: (1) CPO conditions a-e turned into checkable ACs (AC14-AC22); (2) hollow-file, leak and overclaim compensating controls, because the sweeper checks only name and size; (3) attestation bound to content hashes with rebase handling; (4) lint-legal-registers assertion (c) re-run after the second audit file; (5) PR-body plan-path format pitfall that would silently skip the Counsel-Review gate; (6) re-arm tracker ruled a plain issue (no probe, no code).

New considerations: Better Stack hot-window-vs-archive (never `--no-archive`); phase 2 re-sends source summaries (second transmission), not just one extra file; `keep-open` label exists for the tracker; #8281's issue title is unrelated to the marker, cite the module header.

## Overview

The Compound Promotion Loop (#2720) was enabled 2026-07-06 (#6039). Its row in
`knowledge-base/legal/compliance-posture.md` deferred the formal Art. 35 GDPR assessment to "the first 4
weeks of operation"; the soak follow-through #6107 (`earliest=2026-08-03`) has been surfacing daily since,
and the clock is now at ~15 weeks (15 scheduled Sunday runs, 2026-07-12 through 2026-10-18).

This change records the re-evaluation as a committed audit artifact so that
`scripts/followthroughs/dpia-reeval-compound-promote-2720.sh` passes on its own and the sweeper closes
#6107 after merge (the PR carries `Ref #6107`, never `Closes`). The legal determination
("full DPIA required" vs "not required at single-operator scale") is made by the `soleur:legal:clo`
agent during the work phase from facts the work phase gathers; this plan prescribes the evidence, the
artifact shape, the register updates and the attestation path, and does not pre-write the verdict.

No source code changes. `apps/web-platform/server/inngest/functions/cron-compound-promote.ts`, issue
#10552 and issue #8443 are read-only inputs and MUST NOT be edited (another agent is editing the cron;
open WIP PR #10673 `feat-one-shot-compound-promote-server-quorum` touches it).

## Research Insights

### Premise validation (Phase 0.6)

| Cited premise | Check | Result |
|---|---|---|
| #6107 still open, carries the directive | `gh issue view 6107` | OPEN, labels `follow-through`, `needs-attention`, `domain/legal`; directive `script=scripts/followthroughs/dpia-reeval-compound-promote-2720.sh earliest=2026-08-03` |
| Sweeper passes on filename + non-empty regular file | read the script | PASS if `knowledge-base/legal/audits/*dpia*compound-promote*.md` (or `*compound-promote*dpia*`, `*dpia*2720*`) exists, `-f`, `-s`, not a symlink. `2026-10-20-dpia-reeval-compound-promote-2720.md` matches `*dpia*compound-promote*` and `*dpia*2720*` |
| #10552 open, fix PR #10553 merged 2026-10-19 | `gh issue view 10552`, `gh pr view 10553` | issue OPEN (follow-through probe `compound-promote-draft-edit-10552.sh`, `earliest=2026-10-25T06:00:00Z`); PR MERGED 2026-10-19T23:40:34Z |
| Zero draft PRs ever opened | `promotion-log.md` has 0 data rows below the `ROWS BELOW` marker; `gh pr list --label self-healing/auto --state all` returns `[]` | HOLDS for the logged/labelled channel; work phase re-verifies by branch-name search (`self-healing/auto-*`) as a second route |
| Phase 2 sends one extra file per cluster | read `draftAdditiveEdit` | HOLDS and slightly larger than the brief: the phase-2 prompt carries the target file (up to `EDIT_TARGET_MAX_BYTES` = 120,000 bytes), the cluster `rationale` (2,000-char cap) AND re-sends the PII-prefiltered summaries (path + first 10 lines) of that cluster's source learnings a second time. Phase 1 already sends those summaries for the whole corpus |
| Outcome marker field set unchanged | read `compound-promote-marker.ts` | HOLDS: `status, corpus_count, clusters_proposed, clusters_opened, refusals[], refusal_detail[] (cluster_hash, reason, diff_len, diff_fenced, diff_header_pair, diff_hunk), corpus_input_bytes, trigger, run_id, error_class, error_message`; `error_message` is the one free-text field and is redacted + capped at the emitter |
| Weekly cap | `WEEK_CAP_DEFAULT = 2` in the cron | at most 2 clusters per run; the CLO consult asked that the artifact cite the constant, not memory |
| Loop still enabled | `knowledge-base/project/promotion-config.yml` | `enabled: true` |
| Better Stack retention | `betterstack-log-query.md` | source `soleur-inngest-vector-prd` `logs_retention=90` (measured 2026-09-04, #7772; an older learning says 3 days - that was the free tier). 90 days from 2026-10-20 reaches back to ~2026-07-22, but the marker was not machine-readable until #8344 (merged 2026-09-19), so earlier weeks are not derivable from it either way |
| Mechanism vs ADR corpus | ADR-092 is the cron's ADR | no mechanism is being chosen; documentation only, no architectural decision |

### Empirical-data availability (the honest evidence map)

| Figure the issue asks for | Source | Derivable? |
|---|---|---|
| Runs since enablement | schedule arithmetic: Sundays 00:00 UTC, 2026-07-12 .. 2026-10-18 = 15 | arithmetic only, NOT observed (Sentry cron heartbeat proves liveness; work phase may cite it if reachable) |
| Clusters proposed | #10552 body: 2026-09-27, 2026-10-04, 2026-10-11 = 2 each (6), 2026-10-18 = none; plus Better Stack markers since the first post-#8344 run (~2026-09-20) | PARTIAL: ~2026-09-20 onward; weeks 2026-07-12 .. 2026-09-13 not derivable (markers were multi-line console text before #8344; the header of `compound-promote-marker.ts` records that "ten weeks of zero output were undiagnosable" - the marker shipped under the #8281 workstream, whose issue title is the unrelated WikiSkill epic, so cite the module header, not the issue title) |
| Clusters opened (draft PRs) | promotion-log rows; `gh pr list` by label and by head-branch search | MEASURED: 0 across the whole window |
| False-positive rate | needs opened PRs that the operator rejected | NOT MEASURABLE: 0/0, undefined (never write "0%") |
| Operator merge ratio | `gh pr view <n> --json state,merged` on opened PRs | NOT MEASURABLE: 0/0, undefined |
| Refusal-reason distribution | marker `refusals[]` | derivable ~2026-09-20 onward only; every observed proposal was refused `diff-underivable-apply` before the #10553 fix |

The learnings researcher also surfaced: measure data-production rate before relying on a denominator
(`2026-07-06-measure-data-production-rate-before-scoping-a-visibility-surface.md`); field-isolate Better Stack
rows on the decoded `.fn` / boolean discriminator, never substring-match (`2026-07-18-betterstack-followthrough-probe-must-field-isolate-syslog-identifier.md`);
re-derive numerator and denominator two ways before quoting a rate (`2026-07-22-rule-metrics-denominator-investigation.md`);
a counsel sign-off goes stale after a rebase or force-push, so re-verify before merge
(`2026-08-02-the-retraction-pr-was-itself-over-claiming-and-its-counsel-signoff-certified-a-diff-that-no-longer-existed.md`);
legal-substantive decisions route to the CLO agent, not the operator (`workflow-patterns/2026-08-09-legal-decisions-route-to-clo-not-operator.md`);
a status-flip must sweep the legal registers that state the mechanism (`2026-09-27-a-status-flip-sweep-must-include-the-legal-registers-that-state-the-mechanism.md`).
(The researcher could not run content sweeps in its sandbox; treat the list as non-exhaustive.)

### Property List (Phase 0.6b)

1. P1: the sweeper probe passes for #6107 (file exists under `knowledge-base/legal/audits/`, name matches, non-empty regular file).
2. P2: the determination rests on stated empirical evidence, every figure labelled measured / not measurable / not derivable, none fabricated or rounded.
3. P3: the phase-2 data-flow change is recorded (what is sent, to whom, same processor, marker field set unchanged).
4. P4: concrete re-evaluation triggers are pinned in the artifact and in the register.
5. P5: `compliance-posture.md` agrees with the artifact (no stale "deferred 4 weeks / candidate" wording left standing).
6. P6: the legal determination is made by the `soleur:legal:clo` agent and the artifact is marked as an AI-assisted draft pending operator/counsel review per repo convention; the ship Counsel-Review gate is satisfied.
7. P7: #6107 is closed by the sweeper after merge, not by this PR.

### Cut List (Phase 0.6b)

| Mechanism | Property | What already covers it / why cut |
|---|---|---|
| New followthrough script or edit to the existing one | P1 | existing `dpia-reeval-compound-promote-2720.sh` already encodes the pass criterion |
| New ADR / C4 change | - | no architectural decision (docs only) |
| New LIA | P3 | PA-31 already carries the Art. 6(1)(f) basis for the Anthropic-egressing fleet; CLO decides in work whether the data-flow note needs more (consult: pointer in PA-31, no new LIA) |
| `docs/legal/*` or Eleventy mirror policy edits, `legal-doc-shas.ts` re-pin | P3 | CLO consult: no new data subject category or processor; a policy edit would trigger five CI gates for no gain; work phase verifies by reading Privacy Policy / GDPR Policy for a contradicting sentence |
| New marker field or log schema (#8443 UC-1/UC-2) | P2 | forbidden scope; the artifact states "unmeasurable" instead of adding telemetry |
| Waiting for the 2026-10-25 run before recording | P1/P4 | CLO consult: concluding now is defensible because the verdict rests on structural factors (scale, categories, human gate, same processor), not on the ratios; deferring would extend a record already overdue since 2026-08-03. The 10-25 run is a trigger, not a precondition |

### Deepen-plan review dispositions (2026-10-20)

Gates run: 4.6 User-Brand Impact present and valid; 4.7 skipped (pure docs, every Files-to-Edit path under `knowledge-base/`); 4.8 PAT-shaped patterns: no hits; 4.9 no UI; 4.10 no store or connection; 4.11 no guard delivered; 4.12 Scope Check present once, all rows mapped, `inferred` item justified. Citations verified live 2026-10-20: PRs #8344 (MERGED), #10553 (MERGED), #3559/#4463/#6100/#6852/#6875 (MERGED, loop-development PRs), #10673 (OPEN WIP); issues #6107, #10552, #8443, #10551 (OPEN), #6039 and #8281 (CLOSED; #8281's title is the WikiSkill epic, so the "ten weeks of zero output" quote is attributed to the marker module header). Labels `domain/legal`, `type/chore`, `priority/p3-low`, `keep-open`, `follow-through`, `semver:patch`, `self-healing/auto` exist. Rule ids cited (`hr-never-run-commands-with-unbounded-output`, `cq-cite-content-anchor-not-line-number`, `cq-test-fixtures-synthesized-only`) exist in the AGENTS index.

Seats: user-impact reviewer (findings 1-9 folded in as AC14 widening, AC16 widening, AC18-AC22, R7-R9); spec-flow analyzer (10 gaps: 1 lint (c) timing -> Phase 5.4; 2 bare plan path in PR body -> 5.3; 3 PR must exist before the gate -> 5.3 (draft #10674 exists); 4 attestation after rebase / dated-comment conflicts -> 5.5 + AC20; 5 banner vs gate literal -> 5.5; 6 tracker created before verdict -> its body is verdict-agnostic ("re-run the empirical limbs and amend or supersede the memo", valid for either outcome), the CLO may amend it, and if the CLO rules BLOCKED / ship is abandoned the work phase closes it with a note; no probe by CTO ruling D5, the `keep-open` label and the posture Active Item row are the tripwire; 7 #10673 merge-time check -> 5.6; 8 sweeper timing fine, `workflow_dispatch` in Phase 6; 9 not-derivable reasons -> 1.8; 10 phase label -> Phase 1 header); code-simplicity reviewer (dispositions): CUT proposals accepted in part - kept despite the YAGNI seat because each is a hard requirement or a rule: the re-arm tracker (CPO condition d + CTO ruling D5 + deferral-tracking rule), the positive-control query (learning: an empty result through a dead channel is not evidence), the PA-31 note and `anthropic.md` pointer (both already conditional on the CLO finding them inaccurate - the seat's "only if inaccurate" framing is adopted verbatim), the `promotion-config.yml` comment (conditional, CLO decides, D7). Accepted: Phase 1.5 (retention re-measure) is optional - cite the runbook's dated 2026-09-04 measurement when the API call is not reachable; ACs are not merged because each maps to one verifier command.

## Research Reconciliation - Spec vs. Codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| "phase 2 sends one extra public-repo file per cluster" | also re-sends cluster source-learning summaries (second transmission of already-sent data) and the rationale | artifact records all three items; CLO verifies the count of what is sent against the code before attesting |
| "from `self-healing/auto` PRs" | the label-filtered list is empty; the empty result alone cannot distinguish "never opened" from "label never applied" | second route: head-branch search `self-healing/auto-` and `compound-promote` titles (results seen at plan time: only unrelated PRs and loop-development PRs, none loop-opened) |
| "cluster count over ~15 weeks" | not derivable before ~2026-09-20 | artifact says so explicitly |
| Retention "3 days" (old learning) | 90 days (runbook, measured 2026-09-04) | cite the runbook measurement with date; re-measure if reachable |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Close issue #6107: week-4 Art. 35 DPIA re-evaluation for the Compound Promotion Loop (#2720)" | Phases 1-4 (artifact makes the sweeper pass); PR body `Ref #6107` | mapped |
| 2 | "Deliverable: committed audit artifact knowledge-base/legal/audits/2026-10-20-dpia-reeval-compound-promote-2720.md mirroring knowledge-base/legal/audits/2026-06-11-dpia-screening-operator-inbox-triage.md" | Phase 2 (CLO writes it), Files to Create #1 | mapped |
| 3 | "read scripts/followthroughs/dpia-reeval-compound-promote-2720.sh first so filename/content satisfy it" | Premise table row 2; AC1 runs the script | mapped |
| 4 | "Decision (full DPIA required vs not required at single-operator scale) must rest on empirical data ... cluster count, false-positive rate, operator merge ratio" | Phase 1 (gather), evidence map, AC3 | mapped |
| 5 | "Do not fabricate data; state where a figure cannot be derived." | evidence map; AC4 | mapped |
| 6 | "Record data-flow change: phase 2 now sends one extra public-repo file per cluster ... outcome marker field set unchanged." | Phase 2 facts bundle; AC5 | mapped |
| 7 | "Record concrete re-evaluation triggers (first opened draft PR, any change to what is sent to a processor, move off single-operator scale)." | AC6 (plus CLO-added triggers) | mapped |
| 8 | "Legal determination must come from the soleur:legal:clo agent ... mark artifact honestly per repo convention ... and satisfy the ship skill's Counsel-Review CLO-Attestation gate" | Phase 2, Phase 5, AC7-AC9 | mapped |
| 9 | "Update knowledge-base/legal/compliance-posture.md (#2720 row) so register agrees." | Phase 3 | mapped |
| 10 | "PR body uses `Ref #6107` NOT Closes" | Phase 5, AC11 | mapped |
| 11 | "Run whole pipeline through ship, merge and postmerge; ... poll with Monitor tool per ship skill" | Phase 5-6 | mapped |
| 12 | "Do NOT touch #10552, #8443, or apps/web-platform/server/inngest/functions/cron-compound-promote.ts" | Non-goals; AC12 (diff-scope check) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| PA-31 dated note in `article-30-register.md` | "so register agrees" | asked (CLO consult recommends it; conditional on CLO reading PA-31's content cell) |
| Companion counsel-review audit `2026-10-counsel-review-6107.md` | "satisfy the ship skill's Counsel-Review CLO-Attestation gate" | asked |
| Comment-only DATA FLOW line in `knowledge-base/project/promotion-config.yml` | "Record data-flow change" | inferred: that file's header is the operator-facing opt-in statement of what is sent and now omits the phase-2 target file; CLO decides in work (default: add one comment line; skip if CLO finds it unnecessary). Not source code; the YAML value is untouched |
| DPIA index row in the compliance-posture "Legal documents" table | "so register agrees" | asked (sibling DPIA memos are indexed there) |
| `decision-challenges.md` + `tasks.md` under specs | pipeline convention | inferred: workflow artifacts required by plan/ship |

### Split Assessment

- Subsystems touched: 1 - `knowledge-base/legal/` (+ one optional comment line in `knowledge-base/project/`)
- Planned files: 5-6 | Estimated changed lines: ~250-400
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## User-Brand Impact

- **If this lands broken, the user experiences:** a compliance register that states a DPIA is "deferred" or "candidate" while an audit file says it was assessed (or the reverse), so the next reader (operator, a cohort user's counsel, a supervisory authority) cannot tell which statement is current; or a determination that overstates safety ("0% false positives", "no personal data is sent") for a loop that has never produced a reviewable output.
- **If this leaks, the user's data is exposed via:** no new exposure vector (documentation of existing processing; the audit quotes only counts, dates, constants and public file names). The only leak risk is the artifact quoting model output, a learning body or a person-identifying string from the corpus; the work phase must keep the evidence to aggregates.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** CLO-ruled so the ship Counsel-Review gate fires deterministically (the #2720 posture row already carries this threshold, and a wrong Art. 35 determination is a credibility event on the first arms-length user); the lighter `aggregate pattern` was rejected because the gate would then depend on a literal draft marker that must be stripped again in the same PR.

CPO sign-off: obtained at plan time via the CPO consult recorded under Domain Review (`requires_cpo_signoff: true`). `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Domain Review

**Domains relevant:** Legal, Product (sign-off only)

### Legal

**Status:** reviewed
**Assessment:** CLO plan-time consult (advisory, read-only), carried into this plan: screen against Art. 35(3)(a)-(c) and all nine WP248 rev.01 criteria; load-bearing are innovative technology (engaged), involuntary / possibly-named third parties in learnings (partial; the PII prefilter is "a mechanism, not a guarantee"; say best-effort), Art. 22 (not met; draft PR only), large scale (not met), transfers (engaged but covered: SCCs M2+3, Commercial Terms section C). Expected shape mirrors PA-31 (two criteria, one partial, no full DPIA at single-operator scale) but the determination is made in the work phase on the gathered facts. Conclude now, not after 2026-10-25; word empirical basis as measured / not measurable / not derivable; never write "0%". Required edits beyond the audit: #2720 row in-cell plus a dated `Superseded` marker under the "defer 4 weeks / DPIA candidate" sentences (including the line-68 HTML comment and sibling mentions); PA-31 short dated note (conditional on its content cell). Policies / Eleventy mirrors: none. Ship gate: threshold `single-user incident` in plan frontmatter (done), memo status `draft-requires-counsel-review` with the AI-generated DRAFT banner, companion `2026-10-counsel-review-6107.md` SIGNED-OFF by the CLO agent. Additional triggers: loosened or bypassed prefilter, raised target cap (120,000 bytes), target set widened beyond `AGENTS.rules.md` and `SKILL.md`, processor or key change, corpus made private, auto-merge or reduced human gate, first observed PII / Art. 9 leak into model output or a draft PR, marker gaining model-supplied free text, a recipient other than the operator, a new call site, first 5 opened PRs (measure false-positive rate and merge ratio), quarterly Art. 30 cadence. Pitfalls: no line-number citations, no "no PII sent", no past tense for what this PR lands, do not assert 10-25 proves anything, verify "marker carries no free text" against the marker builder (Guard 3 test cited in PA-31), cite the week-cap constant, do not overstate "public repo" (learnings may be authored from private session context).

### Product

**Status:** reviewed
**Assessment:** CPO plan-time consult: `CPO SIGN-OFF: CONDITIONS` (a-e), all folded into this plan as binding wording requirements for the CLO brief and as ACs: (a) the memo says the empirical metrics were not assessable (0/0) and rests only on structural factors (single operator, no cohort users, human-gated draft PRs, never auto-merge); (b) wording is "determination at current scale, conditional, not an empirical finding", never "passed" / "satisfied" (write "re-evaluation performed; empirical limbs deferred to the first opened draft PR"); (c) the three triggers are pinned in the memo AND the posture row; (d) the empirical re-check is re-armed for the first opened draft PR so it cannot rot after the sweeper closes #6107 (mechanism ruled in `decision-challenges.md`); (e) the memo states the actual date performed (2026-10-20) and the delay cause (the 4-week clock was missed; zero draft PRs before the phase-2 fix #10553), without retro-describing it as on schedule. Also: no public or marketing claim from this artifact; the posture row status is updated, not closed. The conditions are met when AC14-AC17 hold.

No Product/UX Gate: no UI surface (docs-only).

**Brainstorm-recommended specialists:** none (no brainstorm).

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` bodies searched for `knowledge-base/legal/compliance-posture.md`, `knowledge-base/legal/audits`, and `knowledge-base/project/learnings/promotion-log.md`: no matches.

## Implementation Phases

Workflow-skill gates that do not fire (recorded so the next reader can see they ran): Observability (2.9) - pure docs, no code/infra path; Encryption posture (2.11) - no store or connection; Guard Contract (2.12) - no guard is delivered (the existing sweeper probe is read, not changed); IaC (2.8), ADR/C4 (2.10), soak enrollment (2.9.1: #6107 is already enrolled by #6039) - none apply; GDPR gate (2.7) - the deliverable IS the GDPR/Art. 35 record and the CLO is its author.

### Phase 1 - Gather evidence (read-only except step 1.9, which writes one GitHub issue; no committed output except the evidence summary the CLO embeds)

Bound every command's output (`head`, `--limit`, `jq` selection) per `hr-never-run-commands-with-unbounded-output`; no SSH anywhere.

1.1 `promotion-log.md`: count data rows below `<!-- ROWS BELOW THIS LINE`. Expected 0. Record the command and count.
1.2 PR search, three routes, all `--state all`: `gh pr list --label self-healing/auto --json number,title,state,createdAt,mergedAt`; `gh pr list --search "self-healing/auto- in:head" ...` (filter out unrelated feature branches that merely contain the words); `gh pr list --search "compound-promote in:title" ...` (filter out loop-development PRs: #3559, #4463, #6100, #6852, #6875, #8344, #10553 and open WIP #10673 are changes TO the loop, not PRs OPENED BY it). Count loop-opened PRs; for any, `gh pr view <n> --json state,merged` to compute merge ratio and rejections.
1.3 Read #10552 body and comments (`gh issue view 10552 --json body,comments`) - source for the 2026-09-27 / 10-04 / 10-11 / 10-18 outcomes. Read-only; do not comment or edit.
1.4 Better Stack read-only marker query (credentials already in Doppler `soleur/prd_terraform`): `doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 90d --grep SOLEUR_COMPOUND_PROMOTE_OUTCOME --limit 200`, decoded structurally (`.raw | fromjson | .message`, field-isolated on `fn == "cron-compound-promote"` and the boolean discriminator, per the shape in `scripts/followthroughs/compound-promote-draft-edit-10552.sh`), with a `SOLEUR_CLAUDE_COST` positive control so an empty result is read as "dark channel" and not "no runs". Do NOT pass `--no-archive`: without the archive arm the query covers only the hot window (~40 minutes) and silently returns a short answer (`scripts/betterstack-query.sh` header, HOT WINDOW vs ARCHIVE); the flags used (`--since`, `--grep`, `--limit`) are the documented convenience flags. Extract per-run: date, trigger, status, clusters_proposed, clusters_opened, refusals[] reason names only (closed enum). If Doppler / credentials are unavailable, record "not derivable: credential not available to this session" and rely on #10552 for the four runs it names. Do not dump raw rows into the artifact.
1.5 Re-measure or cite log retention (`logs_retention` for source 2457081 via the runbook's documented API call, or cite the runbook's dated measurement).
1.6 Read the phase-2 and phase-1 code read-only and record symbol-level anchors (never line numbers): `draftAdditiveEdit`, `readEditTarget`, `EDIT_TARGET_MAX_BYTES`, `WEEK_CAP_DEFAULT`, `DRAFT_EDIT_MAX_TOKENS`, the corpus-collection step (path + first 10 lines, `PII_REGEX` exclusion), `emitOutcomeMarker` and `RefusalDetailEntry` (field set), and that the marker has no model-supplied free text except redacted `error_message`. Cross-check PA-31's description of the cron against these.
1.7 Confirm `knowledge-base/project/promotion-config.yml` still has `enabled: true` and read its DATA FLOW header; read PA-31 in `article-30-register.md` (content-category cell) and the compound-promote lines in `knowledge-base/legal/data-processing-agreements/anthropic.md` (add a pointer only if it enumerates payload categories for this job).
1.8 Write the facts bundle to the session scratchpad (not the repo): each figure labelled measured / not measurable / not derivable, with the command that produced it, AND for every "not derivable" the recorded reason (credential unavailable, channel dark, pre-marker period, no heartbeat access) so the CLO cannot infer "no runs" from a missing instrument.

### Phase 2 - Legal determination and artifact (CLO agent)

2.1 Spawn `soleur:legal:clo` (Task, "do NOT use AskUserQuestion") with the facts bundle, the template memo path, the sweeper script path and the CLO plan-time guidance recorded above. Instruct it to WRITE `knowledge-base/legal/audits/2026-10-20-dpia-reeval-compound-promote-2720.md`:
 - frontmatter mirroring the template (`type: dpia-screening-memo` or a re-evaluation variant it names, `date: 2026-10-20`, `issue: 6107`, `status: draft-requires-counsel-review`, `processing_activity`, `conclusion`, `related`); body opens with the standard AI-generated DRAFT blockquote banner.
 - sections: question re-evaluated and why now (clock expired 2026-08-03); empirical basis table (three-state labelling, evidence map above); data-flow change record (phase 2 target file, re-sent summaries, same processor, marker field set unchanged, week cap 2, cap 120,000 bytes); Art. 35(3) + WP248 screening table; named accepted residual risks; why the remaining surface does not change the conclusion; re-evaluation triggers (the three required + the CLO-added ones above); limitations and what this memo does not establish (10-25 run; ratios 0/0).
 - the file name must keep matching `*dpia*compound-promote*.md`; avoid the strings "Art. 33" / "Article 33" / "33(5)" / "4(12)" so `scripts/lint-legal-registers.sh` assertion (c) does not classify it as a breach determination; no standalone `TBD`/`TODO`/`XXX`/`FIXME` tokens.
 - cite code by symbol, not line; no past tense for anything this PR lands.
2.2 The work agent verifies every factual sentence in the written artifact against the Phase 1 evidence (the CLO makes the legal call; the work agent does not edit the verdict, only reports a fact mismatch back to the CLO for correction).
2.3 If the CLO concludes "full DPIA required", the artifact records that, the posture row becomes an Active Item with a start-DPIA deliverable, and the sweeper still passes (it checks recording, not outcome); do not soften the CLO's answer.

### Phase 3 - Register agreement

3.1 `knowledge-base/legal/compliance-posture.md`: (a) rewrite the #2720 Active Items row in-cell (outcome, link to the artifact, residual risks pointer, triggers pointer, soak follow-through status); (b) append a dated `> **Superseded 2026-10-20 (#6107): ...**` marker after the superseded "defer formal assessment 4 weeks" sentence in the 2026-05-11 HTML comment and wherever else it appears (`rg -n "DPIA candid|week-4|defer formal" knowledge-base/legal/compliance-posture.md`); (c) add a DPIA index row in the legal-documents table beside the other DPIA memos (`Draft (counsel review pending)`); (d) add a standing-trigger Active Item for the first opened draft PR / data-to-processor change, mirroring rows #9545 t7 and #5103; (e) add a dated top-of-file comment line like the neighbours. Run `bash scripts/lint-legal-registers.sh` after (no standalone unresolved marker tokens).
3.2 Conditional per CLO consult: `knowledge-base/legal/article-30-register.md` PA-31 short dated note (phase 2 now also transmits one target file per cluster under the same processor and key; pointer to the memo); `anthropic.md` one-line pointer only if it enumerates payload categories; comment-only DATA FLOW line in `promotion-config.yml`. No `docs/legal/**` edits (verify no contradicting sentence first: `rg -n -i "learnings|repository content" docs/legal/privacy-policy.md docs/legal/gdpr-policy.md`).

3.3 Re-arm tracker, EXECUTED AS STEP 1.9 (before Phase 2, so the CLO can cite its number; the only Phase-1 step that writes, and it writes to GitHub only) (CTO ruling D5, `decision-challenges.md`): create a plain GitHub issue titled `compliance: re-run the empirical DPIA limbs at the first loop-opened draft PR (#2720)` with labels `domain/legal`, `type/chore`, `priority/p3-low`, `keep-open` ("Sweepers must not auto-close this issue"; all four labels verified to exist via `gh label list` on 2026-10-20) and the roadmap milestone the repo uses for compliance chores (`gh issue create --milestone`, taken from `knowledge-base/product/roadmap.md`). Body: trigger "first loop-opened draft PR (first possible run 2026-10-25)"; action "re-run the false-positive rate and operator merge ratio limbs, amend or supersede the memo"; cross-link #10552 (evidence source) and #6107; NO `soleur:followthrough` directive, NO probe script, and no "soak" wording. Reference its number from the memo's trigger section and from the posture Active Item row (create it BEFORE the CLO finalizes the memo so the number can be cited; Phase 2.1 therefore runs after this step, or the CLO is given the number in its brief).

### Phase 4 - Local verification

4.1 `bash scripts/followthroughs/dpia-reeval-compound-promote-2720.sh` exits 0 and prints `PASS: DPIA re-evaluation recorded`.
4.2 `bash scripts/lint-legal-registers.sh` exits 0; `npx markdownlint-cli2` (repo config) clean on changed `.md` files.
4.3 Diff-scope check: `git diff origin/main...HEAD --name-only` contains none of `apps/web-platform/server/inngest/functions/cron-compound-promote.ts`, and no edit to issues #10552 / #8443.

### Phase 5 - Counsel-Review gate (before ship's PR-ready)

5.1 Fresh `soleur:legal:clo` spawn (review, not authoring, for independence) over the diff + implementing files (cron, marker module, PA-31). It writes `knowledge-base/legal/audits/2026-10-counsel-review-6107.md` in the house style of `2026-10-counsel-review-10449.md` (frontmatter `type: counsel-review`, `status: "SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)"`, `disposition`, `blocking_findings`, `conditions`, `re_evaluation_triggers`), returns per-artifact verdicts and DISCHARGED / BLOCKED. Same string rules as 2.1 (no breach-article tokens; or add a `NOT_TRANSCRIBED` waiver in the lint if the CLO must cite them).
5.2 On DISCHARGED: apply conditions; the memo keeps `status: draft-requires-counsel-review` and the DRAFT banner (that is what "pending operator/counsel review" means after attestation; the operator keeps the optional veto and external counsel is reserved for the audit's triggers). Ship emits the `COUNSEL-REVIEW: soleur:legal:clo agent DISCHARGED #6107 (audit: <path>)...` line and continues. On BLOCKED: halt, apply the named fix, re-run. Any rebase / force-push after attestation invalidates it: re-verify (learning above).
5.3 The PR body MUST contain the plan path as the FIRST `knowledge-base/project/(plans|specs)/...` path it mentions, written BARE: the gate extracts it with `[^[:space:])]+`, so a trailing backtick, comma or period is captured into the path, `[[ -f ]]` fails and the gate silently does not fire. Draft PR #10674 already exists, so update its body first (plan path bare on its own line, before any other `knowledge-base/project/` path), then run the gate (`gh pr view` needs the PR). Check by running the gate's own extraction against the body and confirming `[[ -f "$sui_plan" ]]`.
5.4 Re-run `bash scripts/lint-legal-registers.sh` AFTER the counsel-review file exists (Phase 4 ran before it was written): assertion (c) greps every `audits/**/*.md` for `Art. 33`, `33(5)`, `4(12)` and variants, and ~20 existing counsel reviews carry "no breach-article trigger" prose, so the house style invites a hit; a hit would need a `NOT_TRANSCRIBED` waiver in the `.sh` (contradicting the no-`.sh` AC12) so the CLO brief bans those strings in the counsel-review file as well as the memo.
5.5 Rebase / merge-queue handling: the counsel-review file records the git blob hashes of every attested legal file (AC20). After any rebase or queue rebase, recompute them; re-spawn the CLO only if a legal file's content changed (a conflict resolution in the dated top-of-file comment of `compliance-posture.md`, which every PR touching that file edits, is the likely cause - resolve by keeping both lines and re-hash). The DRAFT banner and `status: draft-requires-counsel-review` on the memo are NOT the gate's literal and stay after DISCHARGED.
5.6 Merge-time check of PR #10673 (still OPEN and editing the cron): immediately before merge, `gh pr view 10673 --json state`; if it merged and changed what is sent to a processor, that is one of the memo's own triggers - re-read the cron diff and re-run the CLO before merging this PR.

### Phase 6 - Ship, merge, postmerge

Run `soleur:ship` (CI and the merge queue are slow: poll with the Monitor tool until-loop per the ship skill, never background-sleep). PR title `docs(legal): ...`, body `Ref #6107` and `Ref #2720` (never `Closes`), `## Changelog` section, `semver:patch`. Postmerge: the sweeper (`scheduled-followthrough-sweeper.yml`, daily 18:00 UTC, `workflow_dispatch` available) closes #6107 on the next run; verify with `gh issue view 6107 --json state` and, if still open after the dispatch, read the sweeper comment before concluding. Do not close #6107 by hand and do not comment on #10552.

## Files to Create

1. `knowledge-base/legal/audits/2026-10-20-dpia-reeval-compound-promote-2720.md` (CLO-authored).
2. `knowledge-base/legal/audits/2026-10-counsel-review-6107.md` (CLO attestation).
3. `knowledge-base/project/specs/worktree-agent-aa1d073f6314c9461/tasks.md`, `.../decision-challenges.md` (planning artifacts).

## Files to Edit

1. `knowledge-base/legal/compliance-posture.md` (#2720 row, supersede markers, index row, standing-trigger row, dated comment).
2. `knowledge-base/legal/article-30-register.md` (PA-31 dated note; conditional).
3. `knowledge-base/legal/data-processing-agreements/anthropic.md` (one-line pointer; conditional).
4. `knowledge-base/project/promotion-config.yml` (one comment line only; conditional, CLO decides).

Path globs verified: `knowledge-base/legal/audits/*dpia*compound-promote*.md` matches the planned file name; the other paths exist on `origin/main` (`git ls-files`).

## Acceptance Criteria

- [ ] AC1: `bash scripts/followthroughs/dpia-reeval-compound-promote-2720.sh` exits 0 on the branch (file name matches, non-empty, regular file).
- [ ] AC2: the determination text is authored by a `soleur:legal:clo` spawn (transcript in the session; counsel-review audit names it) and states one of "full DPIA required" / "full DPIA not required at single-operator scale".
- [ ] AC3: the artifact has an empirical-basis table covering cluster count, false-positive rate and operator merge ratio, each cell labelled measured / not measurable / not derivable with the source named; false-positive rate and merge ratio read "0/0, undefined" (or real counts if Phase 1 finds opened PRs), never "0%".
- [ ] AC4: no figure in the artifact lacks a source; weeks before ~2026-09-20 are marked not derivable (unless Phase 1.4 proves otherwise); the run count 15 is labelled schedule arithmetic.
- [ ] AC5: data-flow change recorded: phase 2 transmits the target file (`AGENTS.rules.md` or one `SKILL.md`, cap 120,000 bytes), the cluster rationale and re-sent source summaries to Anthropic (same processor, key and DPA as phase 1); outcome marker field set unchanged and free-text-free except redacted `error_message`; week cap 2 per run.
- [ ] AC6: re-evaluation triggers listed: first opened draft PR; any change to what is sent to a processor (prefilter loosened, cap raised, target set widened, new call site, processor/key change); move off single-operator scale; plus the CLO-added triggers; each is a concrete, checkable condition.
- [ ] AC7: memo frontmatter `status: draft-requires-counsel-review` and the AI-generated DRAFT banner present (honest marking); companion `2026-10-counsel-review-6107.md` exists with `status: "SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)"` and disposition DISCHARGED, or ship halted on BLOCKED.
- [ ] AC8: plan frontmatter keeps `brand_survival_threshold: single-user incident` and the PR body lists the plan path before any other `knowledge-base/project/` path.
- [ ] AC9: CPO sign-off recorded (`decision-challenges.md` row) with no unresolved condition.
- [ ] AC10: `compliance-posture.md` #2720 row no longer says the re-evaluation is pending; it links the artifact and states the outcome; `rg -n "defer formal assessment|week-4 re-evaluation clock STARTED" knowledge-base/legal/compliance-posture.md` shows each remaining hit followed by a dated `Superseded` marker.
- [ ] AC11: `bash scripts/lint-legal-registers.sh` exits 0; markdownlint clean; PR body says `Ref #6107` and does not contain `Closes #6107` / `Fixes #6107` / `Resolves #6107`.
- [ ] AC12: `git diff origin/main...HEAD --name-only` contains no `.ts`/`.sh`/workflow file and not `apps/web-platform/server/inngest/functions/cron-compound-promote.ts`; #10552 and #8443 have no new comments or edits from this work.
- [ ] AC13 (post-merge): #6107 is CLOSED by the sweeper (`gh issue view 6107 --json state`), not by hand.
- [ ] AC14 (CPO a, b): the memo contains the phrases "determination at current scale" and that the empirical limbs were not assessable, and states that the verdict does not rest on the ratios; `rg -n -i "re-evaluation (satisfied|passed)|\bpassed\b|0% false|no personal data|no PII|fully mitigated|\bcompliant\b" <memo>` returns nothing; the memo never calls the corpus "public" without qualification and never states that the #10553 fix works.
- [ ] AC15 (CPO c): the three required triggers appear verbatim-in-substance in both the memo and the posture row.
- [ ] AC16 (CPO d): the re-arm tracker exists per the CTO ruling (`gh issue view <n> --json state,body,labels`: OPEN, body carries the trigger "first loop-opened draft PR" and the action, labels include `keep-open`, no `soleur:followthrough` directive) and `rg -n "#<n>"` hits both the memo and the posture row.
- [ ] AC18 (hollow-file guard; the sweeper checks only name + non-empty): before merge, `rg` on the memo finds a determination sentence ("full DPIA" with "required" / "not required"), a populated empirical-basis table (the three state labels each appear at least once) and a non-empty triggers section containing the three required triggers; the CLO transcript will not exist post-merge, so this is checked on the file.
- [ ] AC19 (leak guard): the memo and the counsel-review file cite only aggregates, constants, dates, closed-enum refusal names and public file names; `rg -n "run_id|cluster_hash|error_message:|BETTERSTACK|doppler" <memo> <counsel-review>` returns nothing (the Doppler value is never echoed, `gh issue view 10552 --json comments` output is paraphrased and not quoted, and no learning body, title or path from the corpus appears).
- [ ] AC20 (attestation bound to content): `2026-10-counsel-review-6107.md` records the git blob hash of the memo it attested (`git hash-object <memo>`), and a pre-merge check re-computes it; any later change to the memo, the posture row or PA-31 (including edits made to satisfy CLO conditions) re-runs the CLO review, and a rebase that alters those files does the same.
- [ ] AC21 ("no public or marketing claim"): the diff touches nothing under `docs/`, `plugins/soleur/docs/` or the Eleventy mirrors.
- [ ] AC22 (CPO e, checkable): `rg -n "2026-10-20" <memo>` and `rg -n -i "missed|overdue" <memo>` both hit, and `rg -n "10553" <memo>` hits.
- [ ] AC17 (CPO e): the memo states the performed date 2026-10-20, that the 4-week clock was missed, and the delay cause (zero draft PRs; phase-2 fix #10553 merged 2026-10-19).

## Test Scenarios

(Docs-only; no unit tests. Layer = shell verification.)

- Given the artifact is absent, when the sweeper script runs, then exit 1 (baseline, run before creating the file, to prove AC1 is not vacuous).
- Given the artifact exists with the planned name, when the script runs, then exit 0 and `PASS`.
- Given a 0-byte file with the planned name, when the script runs, then exit 1 (guards the CLO write path: an empty write must not pass).
- Given the artifact mentions a breach article, when `lint-legal-registers.sh` runs, then it fails on assertion (c); given it does not, it passes (why the strings are banned in 2.1).
- Given `gh pr list --label self-healing/auto` returns `[]`, when the branch-name search also returns no loop-opened PR, then "zero opened" is recorded as measured via two independent routes.
- Given Better Stack returns zero control rows, when grading, then the result is "dark channel, not derivable", never "no runs".
- Given the PR body, when the ship gate resolves the threshold, then the first `knowledge-base/project/(plans|specs)/` path is this plan.

## Success Metrics

Sweeper closes #6107 within one daily cycle after merge; register and artifact agree on the first read; CLO attestation DISCHARGED without conditions that reopen scope.

## Dependencies & Risks

- R1: CLO concludes "full DPIA required". Mitigation: AC2 allows either outcome; follow it (Phase 2.3).
- R2: Better Stack credentials unavailable in this session. Mitigation: record "not derivable"; the verdict does not rest on the ratios.
- R3: Overclaiming ("0%", "no PII sent", "public repo" for corpus authored from private sessions). Mitigation: AC3, CLO pitfalls, fact verification step 2.2.
- R4: `lint-legal-registers.sh` assertion (c) trips on breach-article strings in new audit files. Mitigation: ban in the CLO brief; run the lint in Phase 4.
- R5: Concurrent edits: PR #10673 modifies the cron. Mitigation: never touch it; phase-2 facts are read from `origin/main` at write time and the CLO is told to cite symbols, so a later signature change does not falsify the memo; if #10673 merges before this PR and changes what is sent to a processor, that IS a pinned trigger - re-read the cron diff at Phase 5.
- R6: Stale attestation after rebase. Mitigation: Phase 5.2.
- R7: Time-sensitivity: first proving run is 2026-10-25; if this PR merges after it, add whatever the 10-25 marker shows to the facts (do not wait for it). If the 10-25 marker lands BEFORE merge, re-gather Phase 1.4 and re-run the CLO (AC20), otherwise Phase 5 would attest a stale evidence table.
- R8: If Sentry cron-heartbeat liveness is unreachable, the memo says run counts are "not derivable" beyond schedule arithmetic and must not imply the runs were observed.
- R9: A hollow file passes the sweeper (it checks name, size and regular-file only): AC18 is the compensating control, applied on the file before merge.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails deepen-plan Phase 4.6; this one is filled.
- Use `rg`, not `grep -E 'a|b'`, in worktree-isolated shells; the harness refuses compound pipelines in some agent contexts.
- Do not edit `promotion-log.md` (append-only, owned by the cron).
- The artifact must not claim the #10553 fix works; that is #10552's probe on 2026-10-25.
- Cite code by symbol / constant name, never line number (`cq-cite-content-anchor-not-line-number`).
- Test fixtures / examples in the artifact must be synthesized, never real learning content or personal data (`cq-test-fixtures-synthesized-only`).

## References & Research

- Issue #6107; tracker enrolled by #6039; parent #2720; related #10552, #10553, #8443, #8344, #8281.
- Template: `knowledge-base/legal/audits/2026-06-11-dpia-screening-operator-inbox-triage.md`; sibling DPIA memos `2026-10-05-dpia-screening-agent-web-egress.md`, `2026-07-31-dpia-screening-claude-eval-fleet-and-ci.md`.
- Counsel-review house style: `knowledge-base/legal/audits/2026-10-counsel-review-10449.md`; gate: `plugins/soleur/skills/ship/references/counsel-review-clo-attestation.md`.
- Sweeper: `scripts/followthroughs/dpia-reeval-compound-promote-2720.sh`, `.github/workflows/scheduled-followthrough-sweeper.yml`.
- Runbook: `knowledge-base/engineering/operations/runbooks/compound-promote-runbook.md`; log query: `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`.
