---
title: "fix(legal): interim wording for DPD section 10.3(b) and the pointer in T&C section 14.1b"
date: 2026-10-19
slug: dpd-10-3b-interim-residue-wording
branch: feat-one-shot-dpd-10-3b-interim-residue-wording
issue: 10138
type: fix
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix(legal): interim wording for DPD section 10.3(b) and the pointer in T&C section 14.1b

## Enhancement Summary

**Deepened on:** 2026-10-19. **Method:** the generic 40-agent fan-out was not run: the plan edits one CLO-ruled bullet, one pointer paragraph, a version literal and register markers, and it already carries two CLO rulings, a CPO advisory, a five-seat plan-review panel (simplicity, DHH, Kieran, architecture, spec-flow), a learnings sweep and a worked precedent (PR #10326). Deepening is therefore gate verification plus live re-verification of every cited artifact (the #10326 precedent method).

**Gates (deepen-plan Phase 4.6-4.12):** 4.6 User-Brand Impact present, threshold `single-user incident`, concrete artifact and vector, pass. 4.7 Observability: skipped under the plan Phase 2.9 trigger set (no file under `apps/*/server`, `apps/*/src`, `apps/*/infra` or `plugins/*/scripts`; the touched code files are a version literal, a hash literal and two QA seed scripts), same reading as the #10326 precedent; the plan's skip section is headed `Gates Not Applicable` so a heading grep for an Observability section cannot mistake it for an unfilled one. 4.8 PAT grep: no hit. 4.9 UI wireframe: no UI-surface file (no component, page, layout, `*.njk` or `*.html`); the banner label is a copy string on an existing banner. 4.10 Encryption posture: no `.tf`, migration, cloud-init or compose file and no store or connection. 4.11 Guard contract: the deliverable is wording and pins, not a guard; the ACs are verification of the change. 4.12 Scope check: exactly 1 unfenced `## Scope Check`; 13 asks mapped, provenance rows carry justifications for every `inferred` item, `Recommendation: single PR`.

**Re-verified live in this pass (2026-10-19):** the 2026-10-22 census in the register (14 occurrences; the six `hcloud_volume.git_data` mentions are one in PA-2 (g), three in PA-36 (g), two in PA-36 (f); `(#6897, expires 2026-10-22)` occurs 4 times, so the anchors need leftward extension); the four `Last Updated` openings each occur exactly once; the PA-36 Status anchor occurs once; ADR-239 carries `**Target: 2026-10-22**` once; cited PRs and issues exist with the states claimed (#10132, #10326, #9226, #9839 merged; #10138, #6897, #9066, #7465, #8626, #9051, #10291, #10528 open; #8285 closed and only mentioned as an out-of-scope register cell); cited AGENTS rule ids exist; flip run 39225916196 failed with `flag=unset` (read from the run log); the run list shows no wipe-family run; the posture-register T&C row and the three `TC_VERSION` replicas were found by plan review and added.

**Key improvements carried in from review:** stop mechanism is a plan-level `## Operator Holds` section (ship Phase 6 step 5), not prose; the posture-register T&C row is a fifth `TC_VERSION` replica; AC2 runs word-level over the published surfaces only (CLO ruling B), with internal records allowed three negated phrases; the register ACs compare old spans rather than a file-wide count; HOLD has an exit and artifact; the run list uses a 1000 limit; pins are provisional until Phase 5; any later byte change re-spawns the CLO; `mergeQueueEntry` is read through GraphQL.

**New considerations:** the CLO's own first-round draft contained two negated mentions its second-round rule bans in published text; resolved by ruling B (two replacement sentences). The CLO's round-2 default on publishing the 12 November date differs from round 1; recorded as an owner row, with the date clause cut-able together with its ACs and markers. ADR-239's `Target: 2026-10-22` is bold-wrapped inside a multi-line list item, so the blockquote pointer goes after the whole bullet, indented to stay inside the list item or placed after the list (run markdownlint).

**DRAFT legal wording. Owner review is required before merge. No agent marks this PR ready, enqueues it or merges it.**

Spec lacks valid lane: no `spec.md` exists for this branch, so `lane:` defaulted to `cross-domain` (TR2 fail-closed).

## Overview

> **Review-round note (2026-10-19).** The Phase 2 bullet text, the Last Updated entry and the banner label in this plan are superseded by the CLO review-round rulings recorded in `decision-challenges.md` (rows headed `Review round`). The AC literals that name `12 November 2026`, `19 October 2026`, `14 September 2026`, `retired storage volume` and `We have not finished measuring` follow those rulings (dates as `Month D, YYYY`; `an earlier storage volume`; `We have not measured`).


The published account-deletion statements say deletion is complete: DPD section 10.3(b) ("Encrypted API keys and workspace data are deleted from Hetzner infrastructure.") and T&C section 14.1b ("Workspace data and encrypted API keys are deleted from Hetzner."). Neither mentions that some identifier-bearing operational residue may remain on the retired plaintext git-data volume or on the served store (lock files named with an account identifier, and a progress marker that can hold an account's repository identifier), that the volume has not been destroyed, or that nobody has measured the residue. The full CLO re-ruling is due 2026-10-24 and cannot be completed in full by then, so the CLO agent ruled interim wording. This plan lands it as one mirror-paired legal-docs PR: DPD 10.3(b) (canonical and Eleventy mirror), a one-paragraph pointer in T&C 14.1b (canonical and mirror, which bumps `TC_VERSION` to 2.6.1), the pins that follow, and in-cell markers in the Art. 30 register so the register, the DPD and the T&C stay consistent.

Ref #10138 (item 3). Ref #6897. Draft PR #10528. Due 2026-10-24. The PR body uses `Ref`, never `Closes`, `Fixes` or `Resolves`. This interim wording does not discharge the 2026-10-24 re-ruling.

## Research Reconciliation - Spec vs. Codebase

| Brief or record claim | Reality (checked 2026-10-19) | Plan response |
|---|---|---|
| "A retired storage volume is scheduled for destruction by 12 November 2026" | Not supportable. 2026-11-12 is an outer date: ADR-239 Amendment 2026-10-12 ("at the latest"), `WIPE_OUTER_DATE` in `apps/web-platform/infra/git-data-cutover.sh`, ledger `expires_on`. There is no cron; the destroy needs an owner-named dispatch; two read-only `wipe_check` runs (39081408368, 39136900735) refused at exit 34; `gh run list --workflow git-data-cutover.yml` shows no `wipe`, `wipe_finish` or `snapshot_clear` run | CLO ruled "the latest date by which we intend to destroy", plus "as of <ASOF> it has not been destroyed". "Scheduled" is banned by AC |
| CLO record 2026-10-18 (#6897 comment 6243578371): "10.3(b), T&C 14.1b and the Art. 30 marker already treat residue as unmeasured" | False on disk for 10.3(b) and 14.1b: both say "deleted" and mention no residue. Only the Art. 30 PA-36 marker hedges | CLO corrected its own record (decision-challenges row). The PR body states the correction in the CLO's words; no agent posts it anywhere |
| Fragment: "small operational residue" and "a progress marker that can name a repository" | "Small" is an unmeasured quantity. The marker `.gc-cursor` holds `<auth.users.id>.git`, an account identifier plus `.git`, not a repository name | CLO ruled: drop "small"; say "can hold the identifier of an account's repository" |
| T&C 14.1b "pointer" reads as a small link edit | The T&C is the only `TC_VERSION`-gated document. Any edit needs `TC_DOCUMENT_SHA` re-pinned and, for a non-cosmetic edit, a `TC_VERSION` bump, which redirects every existing user to `/accept-terms` and closes live WebSocket sessions (`recheckTcMidSession`). `TC_VERSION` is also hard-coded in two seed scripts that `check-tc-document-sha.sh` Step 2.5 compares | CLO ruled Tier 2 PATCH, 2.6.0 to 2.6.1. Plan edits `tc-version.ts` and both seed scripts. Merge is an `operator (production-mutating)` row |
| "legal-doc-shas.ts" as the registry for both documents | `terms-and-conditions` is NOT in `LEGAL_DOC_SHAS`; its hash is `TC_DOCUMENT_SHA` in `tc-version.ts`. Only `data-protection-disclosure` is re-pinned in `legal-doc-shas.ts` | Files to Edit reflect both |
| "mirror lint" enforces both documents the same way | T&C is body-equivalence enforced (`BODY_EQUIVALENCE_DOCS` in `check-tc-document-sha.sh`); the DPD is not enrolled (heading parity and Last Updated parity via `legal-doc-consistency.test.ts`, plus the drift ratchet `scripts/lint-legal-mirror-drift-baseline.sh`). Today the DPD Last Updated line is byte-identical on canonical and mirror | Bullet (b) is byte-identical on both copies so the ratchet sees zero new drift; the Last Updated paragraph is prepended identically |
| "The Art. 30 marker must stay consistent" | PA-36 Status says the published statements "are not false today ... and need no amendment now"; PA-36 (f) still says "Target: 2026-10-22". The register has zero mentions of 2026-11-12. Several `expires 2026-10-22` mentions concern OTHER stores (`hcloud_volume.workspaces`, Inngest AOF) | CLO ruled two PA-36 markers plus a census-keyed set of pointer markers on the `git_data` mentions only |
| Measured vs unmeasured must match the runbook vocabulary "printed / computed but not printed / not measured" | Exit 34 prints `repos=0` but discards `lock_residue` and `store_root_repos`, which the host script computes first. Learning `2026-10-18-a-record-pr-said-measured-where-the-evidence-was-printed.md` | Claim-to-evidence table below; published text states no count and no run vocabulary |
| (not in brief) Flip chain | `git-data flip` run 39225916196 (2026-10-19T08:52Z) printed `flag=unset` in its Flag precheck step and then failed at its Flip preconditions step with `verdict=pin_fault_paging_absent` (no flip ran); a `proof` run succeeded five minutes earlier. A flip landing before merge makes the statements load-bearing on real repositories | Pre-merge HOLD condition (flag or stamp set returns to the CLO) |

## Research Insights

**Premise Validation (Phase 0.6).** #10138 and #6897 are OPEN; draft PR #10528 is OPEN. PR #10132 (referenced by #10138) merged 2026-10-12. The cited artifacts exist on `origin/main`: DPD 10.3(b), T&C 14.1b, `legal-doc-shas.ts`, ADR-239, runbook `git-data-luks-cutover-5274.md`, Art. 30 PA-36. Held: the 2026-10-24 due date, the 2026-11-12 outer date as a date. Stale or unsupported: "scheduled" (no job exists), and the CLO's 2026-10-18 statement about the published text. No ADR rejects the mechanism (a qualification in the published sentence): ADR-239 amendments of 2026-10-09 and 2026-10-12 explicitly held published wording pending this re-ruling.

**Property List (Phase 0.6b).**

- P1. A person reading DPD 10.3(b) cannot leave with an unqualified "deleted" and is told that residue may remain, what kind, what has not been done and what has not been measured.
- P2. T&C 14.1b points to DPD 10.3(b) and adds no obligation.
- P3. Canonical and Eleventy mirror carry the same text; every pin and gate that follows is consistent.
- P4. The Art. 30 register does not say the published statements "need no amendment" and does not carry a live-looking 2026-10-22 date for `hcloud_volume.git_data`.
- P5. Every factual clause is no stronger than its evidence class (printed / computed but not printed / not measured / inherited / inferred).
- P6. The PR is visibly a draft requiring owner review and is not merged by any agent.
- P7. Records that state a now-superseded date or a now-false "no amendment needed" for the same store (register, ADR-239, attestation 9066, compliance-posture) do not contradict the published text, and the follow-ups left out of this PR are visible in the posture register (CLO-ruled; each is cut-able only with a CLO yes).

**Cut List.** New Privacy Policy / GDPR Policy / Delete Account dialog edits: no property in the list needs them for the DPD and T&C to be honest (CLO ruled them follow-ups). A new ADR or an ADR-239 amendment: the decision is wording, not architecture; one blockquote pointer on a stale date is enough. New register entry or `last_reviewed` bump: a bump would assert a whole-register review that did not happen. A new lint or guard for the wording: the existing gates plus ACs here cover it. A dated update promise in the published text: the CLO ruled against it. Already covered by existing mechanisms: pin consistency (`check-tc-document-sha.sh`), mirror parity (`legal-doc-consistency.test.ts`, drift ratchet), ruling form (`technical-ruling-gate.sh`).

**Precedent and learnings applied.**

- Precedent: PR #10326 (`knowledge-base/project/plans/archive/20261015-002651-2026-10-14-fix-legal-qualify-in-transit-tls-claim-plan.md`): exact-string replace scripts, word-level diff ACs, byte-level span check, Tier entries prepended to Last Updated, in-cell dated markers with original text preserved, final pin after wording, CLO attestation of the final diff, sibling-PR re-pin rule.
- `2026-10-18-a-record-pr-said-measured-where-the-evidence-was-printed.md`: use the strongest word the evidence licenses and no stronger; never quote private chat; do not attribute a comment by account name.
- `2026-06-15-two-legal-mirror-gates-...`: a new `###` heading needs a mirror heading; prose inside an existing section does not. This plan adds no heading.
- `2026-03-20-eleventy-mirror-dual-date-locations.md`: the mirror has a hero `<p>` and a body line; grep both (`Last Updated[: *]+<D>`).
- `2026-05-22-dpa-template-pre-draft-...`: keep script paths and engineering detail out of the DPD Last Updated entry.
- `2026-07-16-removing-a-false-claim-...`: do not offer "re-pin, no bump" for a non-cosmetic T&C edit.
- `2026-09-07-...`: on a `legal-doc-shas.ts` conflict recompute the pin from the merged canonical; never take either side.
- `best-practices/2026-06-30-github-merge-queue-adoption-...` and `workflow-patterns/2026-10-07-merge-queue-silent-ejection-re-enqueue.md`: the T&C bump bypass reads the merge-group base; a stale pin shows up only on the queue.
- `2026-05-16-legal-prose-vocabulary-refactors-implicate-operational-runbooks.md`: runbook grep done; the runbook has zero 2026-10-22 mentions and the "Hold the first run that prints the residue counts" sentence stays true (an interim text is not the re-ruling).

**Baseline gates on this branch before any edit (2026-10-19).** `scripts/lint-legal-mirror-drift-baseline.sh --base origin/main`: pass with the pre-existing #7465 overdue warning (80 drift lines). `check-tc-document-sha.sh`: pass. `scripts/lint-legal-registers.sh`: 11 assertions, 0 failed. `scripts/probe-legal-corpus-truth.sh`: CORPUS-OK.

**GDPR gate (Phase 2.7, advisory, not legal review).** Fired on trigger (b), brand-survival threshold `single-user incident`; no canonical-regex path (no schema, migration, auth, API or `.sql` file) is touched, so the five schema checks (Art. 6, 5(1)(e), 17, Chapter V, Art. 9) have nothing to match. Observations only: the change discloses retention the earlier sentence did not describe (Art. 13(2)(a), Art. 5(1)(e)); the date the volume outlives its stated target is already recorded as a storage-limitation overrun in ADR-239 Amendment 2026-10-12; no new processing purpose, sub-processor, recipient or transfer. No Critical finding, so no `compliance-posture.md` Active Items write is triggered by the gate itself (the CLO-ruled follow-up row below is a separate, CLO-directed row).

### Claim-to-evidence table (CLO-ruled, 2026-10-19)

| Added claim | Evidence class | Published form |
|---|---|---|
| API keys and workspace data deleted from Hetzner | INHERITED (prior published sentence) | kept as the verbatim prefix |
| Lock files named with an account identifier may remain | INFERRED (pre-#9226 wrappers wrote `.<id>.init.lock`, ADR-239 2026-10-09); existence NOT MEASURED (`lock_residue` COMPUTED BUT NOT PRINTED, exit 34 discards it) | "may remain", "we do not yet know whether any exist" |
| Since 14 September 2026 | INHERITED (host and volume created 2026-09-14, ADR-239) | start anchor only |
| Marker can hold the identifier of an account's repository | INFERRED (`git-data-gc.sh` writes `<id>.git`); presence NOT MEASURED | "can hold" |
| The retired volume "may hold" the lock files | NOT MEASURED | "may" |
| Volume not destroyed as of <ASOF> | INFERRED (run list and volume read on <ASOF>) | dated by the read |
| 12 November 2026 as latest intent | INHERITED (ADR-239, `WIPE_OUTER_DATE`, ledger `expires_on`) | "the latest date by which we intend to destroy" |
| Destroying the volume does not reach anything held elsewhere | INFERRED (marker sits at the root of the served store) | "ends that volume only, and leaves a marker or lock files on any other storage as they are" |
| Description may be incomplete | PRINTED for the off-list count (`has_hooks_d=1 offlist_n=1`, run 39136900735); contents NOT MEASURED | "may not be complete"; `hooks` is never named |
| Hetzner copy retention | NOT MEASURED (PA-36 (f), CLO standing line) | "we have not measured" |

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (200 limit, two-stage jq) returned no issue whose body names any file in Files to Edit or Files to Create.

## Decisions Already Ruled (planning phase)

All rows are in `knowledge-base/project/specs/feat-one-shot-dpd-10-3b-interim-residue-wording/decision-challenges.md` (30 rows; `technical-ruling-gate.sh --branch` PASS). A CLO ruling on legal posture is recorded with Class `operator (legal-risk)` per `technical-ruling-delegation.md` section 6. Binding on the implementation:

- Ruled by CLO agent, 2026-10-19: DPD 10.3(b) final text, T&C pointer text, Tier 2 PATCH bump to 2.6.1, DPD Tier 1 for the attestation record, "Amended" (not "Corrected"), no promise to update, date wording, as-of rule, two PA-36 markers, census-keyed pointer markers, forbidden-word AC mechanics, banner label, date roles, pre-merge read procedure and HOLD conditions.
- Ruled by CLO agent, 2026-10-19: Privacy Policy, GDPR Policy and the Delete Account dialog are NOT amended in this PR.
- Four operator rows: merge with the `TC_VERSION` bump (production-mutating); publishing the 2026-11-12 date (legal-risk); follow-up scope (scope); follow-up order (priority); plus the tracking-issue row (scope). None is a technical question.
- CPO advisory: SIGN-OFF WITH CONDITIONS (below, Domain Review).

## Operator Holds

- Hold: Operator-reserved: owner review of the draft legal wording and the owner's own merge of it (merge forces every existing user to re-accept the Terms and closes live sessions); no agent marks this PR ready, enqueues it or merges it.

## Pipeline stop rule (load-bearing)

The one-shot pipeline normally treats a draft PR as not done and ships to a merged PR. Here the mechanism that stops it is the `## Operator Holds` section above (`soleur:ship` Phase 6 step 5, `references/operator-holds.md`, `hold-gate-eval.sh`): a hold whose words begin `Operator-reserved:` always stands, and with no `Delegation:` line the evaluator exits 3, which sends ship to the by-hand prose path (operator-holds.md section 3). Ship may push the branch, update the PR title and body, and run the gates; it must not run `gh pr ready` or `gh pr merge` and must not add the PR to the merge queue, and the run ends WITHOUT the DONE promise (as one-shot does for a stall). If the owner later enqueues the PR, no agent pushes or syncs while it is queued.

## Files to Edit

Anchors, not line numbers (`cq-cite-content-anchor-not-line-number`); locate each by the strings given.

1. `docs/legal/data-protection-disclosure.md` - bullet `- **(b)** Encrypted API keys and workspace data are deleted from Hetzner infrastructure.` in section 10.3; the opening of the `**Last Updated:** October 15, 2026 *(` paragraph.
2. `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` - the same bullet; the same Last Updated opening; the hero `<p>Effective February 20, 2026 | Last Updated October 15, 2026</p>`.
3. `docs/legal/terms-and-conditions.md` - new paragraph after the three bullets of `### 14.1b Termination of Web Platform Account` and before `If a Subscription is active at the time of account deletion`; the `**Last Updated:** October 8, 2026 *(` opening.
4. `plugins/soleur/docs/pages/legal/terms-and-conditions.md` - the same paragraph (mirror link form `/legal/data-protection-disclosure/`); the same Last Updated opening; the hero `<p>`.
5. `apps/web-platform/lib/legal/tc-version.ts` - `TC_VERSION` 2.6.0 to 2.6.1; `TC_DOCUMENT_SHA`; `TC_BUMP_METADATA.lastUpdated` and `substantiveChange`.
6. `apps/web-platform/scripts/seed-dev-users.sh` and `apps/web-platform/scripts/seed-qa-user.sh` - `TC_VERSION="2.6.0"` to `"2.6.1"` (Step 2.5 parity; otherwise QA users loop on `/accept-terms`).
7. `apps/web-platform/lib/legal/legal-doc-shas.ts` - the `"data-protection-disclosure"` hash only.
8. `knowledge-base/legal/article-30-register.md` - PA-36 `(f) Retention` (end-of-cell marker, one clause governing both 2026-10-22 mentions, and M2 after the ledger citation); PA-36 `Status` (marker); M1 after the `hcloud_volume.git_data ... expires 2026-10-22` mention in PA-2 (g) and after each of the three `(#6897, expires 2026-10-22)` mentions in PA-36 (g). Not touched: the PA-1 (g) and second PA-2 (g) mentions (`hcloud_volume.workspaces`, deleted 2026-10-08) and the Inngest AOF cells (#8285).
9. `knowledge-base/engineering/architecture/decisions/ADR-239-git-data-serves-from-luks-at-birth.md` - one blockquote pointer after the 2026-10-09 amendment bullet that says `Target: 2026-10-22`.
10. `knowledge-base/legal/audits/2026-10-counsel-attestation-9066.md` - pointer inside the quoted `re_evaluation_triggers` item (1) and one body blockquote after the sentence that calls 2026-10-22 a target; the YAML frontmatter must still parse.
11. `knowledge-base/legal/compliance-posture.md` - (i) the `| Terms & Conditions | ... | 2.6.0 | 2026-10-08 | Active |` row: version cell to `2.6.1` and date cell to `<D-ISO>` (the "fifth replica" that `check-tc-document-sha.sh` compares to `TC_VERSION`; plan review found it missing); (ii) one new Active Items row for the Delete Account dialog, Privacy Policy and GDPR Policy follow-ups (CLO round 2), in the table's five-column schema, no date marker.

## Files to Create

- `knowledge-base/legal/audits/2026-10-19-clo-attestation-10138-interim-dpd-10-3b-wording.md` - CLO agent attestation of the FINAL diff (precedent: `2026-10-15-clo-attestation-10136-in-transit-tls-correction.md`): `tier_classification` DPD Tier 1, T&C Tier 2, v1 internal attestation, scope "the wording in this PR only", the open items, and re-evaluation triggers. Avoid the strings `4(12)`, `33(5)` and `Art. 33` (the `lint-legal-registers.sh` determination pattern, check (c)), or add a NOT_TRANSCRIBED waiver.
- `knowledge-base/project/specs/feat-one-shot-dpd-10-3b-interim-residue-wording/tasks.md` (derived) and `decision-challenges.md` (already created at plan time).

No other file is created or edited. No workflow dispatch, `terraform apply`, Doppler write, volume wipe or destroy, issue post or comment is part of this plan.

## Implementation Phases

Edit with an exact-string replace per file (the Edit tool or a small `python3 -I` script reading and writing UTF-8; never `sed` on these very long lines). Assert each old string occurs exactly once before replacing. `<D>` is the edit day (`Month D, YYYY` in Last Updated and `TC_BUMP_METADATA`, `YYYY-MM-DD` in markers); `<ASOF>` is the UTC date of the Phase 1 reads, written `D Month YYYY` inside the DPD bullet (for example "19 October 2026").

### Phase 0 - Start (work phase)

0a. `git fetch origin main && git merge origin/main` (or rebase per the work skill) BEFORE any legal edit: the legal file set and the Last Updated chains move under sibling PRs. Re-run the four baseline gates and confirm they still pass.

0b. Confirm the PR is still a draft and not in the merge queue: `gh api graphql -f query='{repository(owner:"jikig-ai",name:"soleur"){pullRequest(number:10528){isDraft mergeQueueEntry{id}}}}'` (gh 2.102.0 has no `mergeQueueEntry` field on `gh pr view --json`). If `mergeQueueEntry` is non-null, STOP: do not push or sync.

### Phase 1 - Pre-merge reads (plain reads, no dispatch, no authorization needed - CLO)

Run and record in `session-state.md` and in the PR body (command shapes, UTC timestamps and results only; never token values; there is no separate record file):

```text
read_utc_start / read_utc_end: date -u +%FT%TZ     as_of_date = UTC date of read_utc_start
1. volume: the runbook's read-only provider read (Doppler prd_terraform, HCLOUD_TOKEN_READONLY,
   GET /v1/volumes?name=soleur-git-data-store, id / attached_to / delete_protected) -> exactly one volume,
   id 106867358; its actions (GET /v1/volumes/<id>/actions?sort=id:desc&per_page=5) -> none running, latest
   command is not a detach or delete.
2. runs:  gh run list --workflow git-data-cutover.yml --limit 1000 \
            --json databaseId,displayTitle,createdAt,status,conclusion,event,headBranch
   -> total < 1000; no non-completed run; zero titles matching ^git-data (wipe|wipe_finish|snapshot_clear)( |$);
      no wipe_check with conclusion success; record the newest run.
3. flag and stamp: doppler secrets get GIT_DATA_STORE_ENABLED  --plain --no-exit-on-missing-secret -p soleur -c prd
                   doppler secrets get GIT_DATA_LUKS_CUTOVER_AT --plain --no-exit-on-missing-secret -p soleur -c prd
   -> exit 0 on both; flag false or empty; stamp empty. A non-zero exit is a HOLD, never "false".
```

HOLD (return to the CLO, do not proceed to Phase 2): volume absent, more than one listed, a different id, or a detach/delete action; any `wipe`, `wipe_finish` or `snapshot_clear` run in any status; any non-completed `git-data-cutover` run; flag `true` or stamp present, or a non-zero exit; a successful `wipe_check`; a run list as long as its limit (1000; the workflow has far fewer runs today, and a date filter replaces the limit if that ever changes), or a `gh` auth or rate-limit failure; a merge on or after 2026-11-12, or after 2026-10-24 when the CLO has meanwhile re-ruled, also holds (the "latest date" sentence or the interim status is then false). **HOLD exit:** write `HOLD: <condition>, <UTC time>` to `session-state.md` and the top of the PR body, leave the PR a draft, make no Phase 2-4 edit (or revert uncommitted ones), and end the run without a DONE promise; the owner or the next session re-runs Phase 1 once the cause clears, and the CLO is re-spawned only for the conditions listed above (an unavailable read is retried, not ruled). If Doppler or the provider read is unavailable to the session, that is itself a HOLD; do not substitute the log of an older flip precheck for the stamp read except as a dated, weaker source (a run created on the as-of date with no later `git-data-cutover` run).

### Phase 2 - DPD 10.3(b) (canonical then mirror, same session)

Old: `- **(b)** Encrypted API keys and workspace data are deleted from Hetzner infrastructure.`

New (CLO-ruled text; canonical and mirror byte-identical; the bullet has no links):

`- **(b)** Encrypted API keys and workspace data are deleted from Hetzner infrastructure, except for the residue described in this item. Some operational residue may remain after deletion if your account was deleted on or after 14 September 2026: lock files whose names carry an account identifier, and a progress marker that can hold the identifier of an account's repository. We have set 12 November 2026 as the latest date by which we intend to destroy a retired storage volume that may hold some of those lock files; as of <ASOF> it has not been destroyed, and destroying that volume ends that volume only, and leaves a marker or lock files on any other storage as they are. We have not finished measuring this residue: we do not yet know whether any such lock file or marker exists or how many, this description may not be complete, and we have not measured whether Hetzner keeps a copy of the retired volume after it is destroyed. *(Amended <D-ISO>: this item previously read "Encrypted API keys and workspace data are deleted from Hetzner infrastructure." and did not mention this residue.)*`

Use the straight apostrophe the document uses. Do not touch the closing line `See the [Terms and Conditions](terms-and-conditions.md) Section 14.1b ...`. Do not name the volume id, a run id, `hooks`, `repos=`, `lock_residue`, any count or any listing name.

**Last Updated** (canonical, mirror body, mirror hero date): change `**Last Updated:** October 15, 2026 *(` to `**Last Updated:** <D> *(<ENTRY>)* Previous: October 15, 2026 *(`, leaving the existing chain intact. `<ENTRY>` (CLO-ruled): `Section 10.3(b) (Web Platform account deletion) now says that some operational residue may remain after deletion if an account was deleted on or after September 14, 2026: lock files whose names carry an account identifier and a progress marker that can hold the identifier of an account's repository. It also says that a retired storage volume that may hold some of it has not been destroyed as of <ASOF-LONG>, that we intend to destroy it by November 12, 2026 at the latest, and that we have not finished measuring the residue or what Hetzner keeps after a volume is destroyed. **This qualifies an earlier statement that did not mention this residue; it is a disclosure of retention the earlier statement did not describe, not a new purpose, sub-processor, recipient or international transfer.** It does not claim that the residue exists, how much there is, or that it has been dealt with.` No PR or issue numbers, no script paths, no run ids. Date-order the entry against #10291 and #9051 on rebase.

### Phase 3 - T&C 14.1b pointer, version bump and pins

3a. Insert one new paragraph (blank line before and after) after the three 14.1b bullets, before `If a Subscription is active at the time of account deletion`:

Canonical: `The second bullet above is subject to Section 10.3(b) of the [Data Protection Disclosure](data-protection-disclosure.md), which describes operational residue that may remain after deletion.`

Mirror: the same sentence with the link target `(/legal/data-protection-disclosure/)`. Leave the three bullets and the closing Privacy Policy sentence untouched. No obligation language.

3b. T&C Last Updated (canonical, mirror body, mirror hero): prepend `**Last Updated:** <D> *(Section 14.1b now says that the deletion it describes is subject to operational residue that may remain after account deletion, which is described in Section 10.3(b) of the Data Protection Disclosure. **This adds a cross-reference and a qualification to an earlier statement; it creates no new obligation for you and no new purpose, sub-processor, recipient or international transfer.**)* Previous: October 8, 2026 *(`.

3c. `apps/web-platform/lib/legal/tc-version.ts`: `TC_VERSION = "2.6.1"`; `TC_DOCUMENT_SHA` = `sha256sum docs/legal/terms-and-conditions.md` (provisional until Phase 5, which sets the final value); `TC_BUMP_METADATA.lastUpdated = "<D>"` (matches `/^[A-Z][a-z]+ \d{1,2}, \d{4}$/`); `TC_BUMP_METADATA.substantiveChange = "Account deletion: some files linked to your account may remain on retired storage after deletion, as described in the Data Protection Disclosure"` (CLO-ruled; no period; the banner appends one; matches `/^[§A-Z][^.]{9,}$/`; diff its categories against the DPD bullet). `fullTermsUrl` unchanged. `TC_VERSION` here is the T&C version, not a plugin version file (`wg-never-bump-version-files-in-feature` does not apply).

3d. `TC_VERSION="2.6.1"` in `seed-dev-users.sh` and `seed-qa-user.sh`.

3e. `LEGAL_DOC_SHAS["data-protection-disclosure"]` = `sha256sum docs/legal/data-protection-disclosure.md` (provisional until Phase 5). Touch no other key.

3f. `knowledge-base/legal/compliance-posture.md` T&C row: version cell `2.6.1`, date cell `<D-ISO>` (Phase 4h adds the new follow-up row).

### Phase 4 - Art. 30 register and sibling records (CLO-ruled markers)

Edit by content anchor in `knowledge-base/legal/article-30-register.md` with an exact-string insertion that PRESERVES all original text. Markers are merge-conditioned (no past tense about main: "fires on the merge of the draft PR carrying this marker"). `<d>` is the edit day (`YYYY-MM-DD`).

4a. **PA-36 (f)**, appended after the existing marker at the end of the cell:

`**[Superseded <d> (#6897; fires on the merge of the draft PR carrying this marker, not before), as to "Target: 2026-10-22, the ledger `expires_on`": the outer date has been 2026-11-12 at the latest since ADR-239 Amendment 2026-10-12 (ledger `expires_on` 2026-11-12). It is an outer date, not a scheduled job: the destroy needs the owner to name a dispatch, two read-only `wipe_check` runs refused at exit 34 on 2026-10-18 (printed in the public run log), and the run list read on <ASOF-ISO> shows no `wipe`, `wipe_finish` or `snapshot_clear` dispatch. On that merge DPD §10.3(b) and T&C §14.1b will say that operational residue (lock files whose names carry an account identifier; a progress marker that can hold an account's repository identifier) may remain after deletion for accounts deleted on or after 2026-09-14, that the retired volume has not been destroyed as of <ASOF-ISO> with 2026-11-12 the latest intended date, and that the residue, the volume's other contents and provider-side copies are not yet measured. This marker does not say the files exist, how many there are, or that they are gone. Hetzner snapshot or backup retention stays unmeasured, and destroying the device ends that device only, not the cursor or lock files on any other store. This marker governs both 2026-10-22 mentions in this cell: the `expires_on: 2026-10-22` in the ledger citation and the "Target: 2026-10-22" in the 2026-10-09 marker. Both are superseded by ADR-239 Amendment 2026-10-12; the ledger date is 2026-11-12.]**`

4b. **PA-36 Status**, appended at the end of the cell:

`**[Superseded <d> (#6897; fires on the merge of the draft PR carrying this marker), as to "are **not false today** (nothing exists to be un-deleted) and need no amendment now" and as to "the host is unborn": the plaintext volume has existed since 2026-09-14 and the residue named in the (f) marker may remain on it, unmeasured, so those statements are amended in that PR and neither says the residue is gone. The statements still become load-bearing on repositories at the cutover, when (g)(3) must be closed or they qualified; the in-product Delete Account dialog and the Privacy Policy and GDPR Policy retention bullets are not amended by that PR. The classification "Declared, not live" is unchanged: `GIT_DATA_STORE_ENABLED` read `unset` at the 2026-10-19 flip precheck (printed in the public run log).]**`

(If Phase 1 shows a later flag read, state that read instead of the 2026-10-19 precheck.)

4c. **M2**, directly after the ledger citation `expires_on: 2026-10-22`) inside PA-36 (f): `**[Superseded <d> (#6897), as to "expires_on: 2026-10-22": see the PA-36 (f) marker at the end of this cell. Fires on the merge of the draft PR carrying this marker.]**`

4d. **M1**, after the PA-2 (g) mention `hcloud_volume.git_data` stays a recorded exception (#6897, expires 2026-10-22)` and after EACH of the three `(#6897, expires 2026-10-22)` mentions in PA-36 (g) (four insertions). The bare string `(#6897, expires 2026-10-22)` occurs 4 times in the file, so extend each anchor leftward with enough surrounding words that it occurs exactly once, and assert that before inserting: `**[Superseded <d> (#6897), as to "expires 2026-10-22": ADR-239 Amendment 2026-10-12 supersedes that date; the ledger row for `hcloud_volume.git_data` reads `expires_on: 2026-11-12` at the time of this marker, an outer date, not a plan. See the PA-36 (f) marker of this date. Fires on the merge of the draft PR carrying this marker.]**`

4e. Do NOT edit the digits of any `2026-10-22`; do NOT edit PA-1 (g) and the second PA-2 (g) mention (`hcloud_volume.workspaces`) or the Inngest AOF cells (#8285); do NOT bump `last_reviewed`; do NOT change the ledger `disclosed_as` for `hcloud_volume.git_data` (it stays `not-publicly-claimed`).

4f. **ADR-239**: after the 2026-10-09 amendment's retention bullet that says `Target: 2026-10-22`, add `> **Superseded 2026-10-12 (#6897), as to "Target: 2026-10-22": see Amendment 2026-10-12 below; the outer date is 2026-11-12. Pointer added <d>, fires on the merge of the draft PR carrying it.**` The mention inside "Amendment 2026-10-12" is the superseding text and gets no marker.

4g. **Attestation 9066**: append an M1-style pointer inside the quoted `re_evaluation_triggers` string at item (1) and a body blockquote after the sentence that calls 2026-10-22 a target; verify the frontmatter parses (`python3 -I` with a YAML load, or the repo's frontmatter reader).

4h. **compliance-posture.md**: besides the T&C version row of 3f, one row in the Active Compliance Items table (five fixed columns: Item, Issue, Status, Deadline, Notes) for aligning the Delete Account dialog (before any flip), Privacy Policy section 7 and GDPR Policy section 8.4 (at the 2026-10-24 re-ruling) with the interim DPD 10.3(b) statement; Issue `#6897`/`#10138` as references only, Status OPEN. No date marker elsewhere in that file.

### Phase 5 - Attestation and final pin

1. Finish every wording edit first. 2. Set every edit-day value to the day of the last push that changes that document's bytes: Last Updated on canonical, mirror body and mirror hero (DPD and T&C separately), `TC_BUMP_METADATA.lastUpdated`, the `Amended` date, the `Superseded <d>` dates. 3. Recompute and paste `TC_DOCUMENT_SHA` and `LEGAL_DOC_SHAS["data-protection-disclosure"]`. 4. `git fetch origin main && git merge origin/main` once more; if a sibling moved a legal file, recompute both pins from the merged canonical files (a sibling that bumped `TC_VERSION` to a different value than 2.6.1 is a conflict on `tc-version.ts`, the seed scripts and the posture row: take the higher version, bump to the next PATCH of it, and have the CLO re-attest). 5. Run Phase 6. 6. Spawn the CLO agent with the FINAL diff (Tier 1 DPD, Tier 2 T&C) for attestation and write the attestation file; record the verdict as `Ruled by CLO agent, <date>: ...`. 7. If the day rolls over afterwards, repeat steps 2 to 3 for the affected document only AND re-spawn the CLO to re-attest the changed bytes (the attestation is invalidated by any later byte change). The as-of date is NEVER defaulted to the edit day; a push that only refreshes the as-of date touches the DPD bullet, its Last Updated entry, the register markers and `legal-doc-shas.ts` only, and never re-dates or re-hashes the T&C.

### Phase 6 - Verification

```bash
sha256sum docs/legal/terms-and-conditions.md docs/legal/data-protection-disclosure.md   # equal the two literals
bash apps/web-platform/scripts/check-tc-document-sha.sh                                  # rc=0 (T&C bump bypass + seed parity)
bash scripts/lint-legal-mirror-drift-baseline.sh --base origin/main                      # rc=0; the #7465 overdue warning is pre-existing
bash scripts/lint-legal-registers.sh                                                      # all assertions passed
bash scripts/lint-legal-scope-block-placement.sh                                          # added-lines-only; passes on the unedited tree
bash scripts/probe-legal-corpus-truth.sh                                                  # CORPUS-OK
bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch feat-one-shot-dpd-10-3b-interim-residue-wording
(cd apps/web-platform && npx vitest run test/legal-doc-consistency.test.ts test/legal-doc-shas-guard.test.ts test/tc-version.test.ts test/accept-terms-copy-regression.test.tsx)
npx markdownlint-cli2 <the markdown files edited above>    # only if it ran green on origin/main for them
```

If a gate goes red, fix the edit; never loosen a baseline, renew an exception or add a waiver. Do not run `test-all --affected` (CI's required `test` context covers the rest).

### Phase 7 - PR marking, then stop

Update draft PR #10528: title prefix `DRAFT legal wording - owner review required before merge:` followed by the conventional title; body opens with a bold DRAFT banner. Body content: `Ref #10138` and `Ref #6897` only; Tier 1 (DPD) and Tier 2 (T&C) with the CLO reasoning and the Tier 1 MINOR dissent; the forced re-acceptance consequence in plain words; the CLO's correction of its 2026-10-18 record (stated, not posted); that this is interim and does not discharge the 2026-10-24 re-ruling and when it re-opens; the unchanged surfaces (Delete Account dialog still says "permanently deleted"; Privacy Policy section 7 and GDPR Policy section 8.4 still say "deleted"); the operator rows from decision-challenges.md; the claim-to-evidence table; the pre-merge read record (this is its only home besides `session-state.md`); the sibling-PR sequencing note; the count of real web-platform accounts that the bump will redirect when a read-only source exists (otherwise "not counted" with the reason); ready-to-file text for the follow-up issues (the owner files or names #10138 and #6897 sufficient); and, in plain words, that no agent posted anywhere. Then STOP at the draft (Pipeline stop rule).

### Pre-enqueue (owner says go; an agent session, never while queued)

Re-run Phase 1 and the Phase 5 re-merge. If the as-of date is older than the merge day or the day before, push a DPD/register-only refresh (bullet as-of, DPD Last Updated entry, register markers, `legal-doc-shas.ts`; no T&C change) and re-run the gates BEFORE enqueue; the CLO re-attests any byte change. Recompute the pins from the merged canonical files; never take a sibling's literal. Ask the owner to hold flip and wipe-family dispatches from enqueue to merge and to have an agent re-run Phase 1 at dequeue or just before merge if the queue takes more than a day (the flag or stamp can move after Phase 1). If main moves while queued and `tc-document-sha-guard` goes red on the merge-group ref, the owner dequeues first.

## Acceptance Criteria

Diff checks use word-level added text because the touched register and Last Updated lines are single paragraphs of 1 to 70 KB whose pre-existing text already contains most banned words (measured in plan review: the DPD Last Updated line alone has `removal` x6, `scheduled` x4, `commitment` x2). Define `ADDED() { git diff -U0 --word-diff=porcelain origin/main...HEAD -- "$@" | grep -E '^\+[^+]'; }` and always name the files: the PUBLISHED SURFACES are `docs/legal/data-protection-disclosure.md`, `docs/legal/terms-and-conditions.md` and their two mirrors plus the `substantiveChange` string in `tc-version.ts`; the INTERNAL RECORDS are the register, ADR-239, attestation 9066, `compliance-posture.md` and the new attestation file. Never run a banned-word grep over the plan, `decision-challenges.md` or a whole-line diff. A throwaway `python -I` script kept out of the repo applies each intended replacement to the `origin/main` version, asserts every old span occurs exactly once and that the result is byte-identical to the working file (the byte-level span check; the word-diff is a reviewer aid).

### Pre-merge (PR)

- [ ] AC1. DPD bullet (b) equals the Phase 2 text exactly in canonical and mirror and the two bullet lines are byte-identical; the original sentence `Encrypted API keys and workspace data are deleted from Hetzner infrastructure` occurs exactly 2 times on that line (live prefix, then inside the `*(Amended` span between quotation marks) and 0 times elsewhere in added DPD text (count with `grep -o | wc -l`, not `grep -c`); `12 November 2026` occurs once in the bullet; each of `except for the residue described in this item`, `may remain after deletion`, `have not measured whether Hetzner keeps a copy` occurs in it; every `has not been destroyed` has the literal `as of` within 120 characters before it; `scheduled for destruction` has no added hit in `docs/legal`, `plugins/soleur/docs/pages/legal` or `knowledge-base/legal`.
- [ ] AC2. Forbidden words, `ADDED` over the PUBLISHED SURFACES only (the DPD bullet, DPD and T&C Last Updated entries, the T&C pointer, the banner label): zero hits, with NO allowlist and no negated mention (CLO ruling B, 2026-10-19), for `removed|removal|removes|remove|gone|cleared|committed|commitment|scheduled|schedule|erased|purged|wiped|scrubbed|deleted completely|permanently|all traces|clean|empty|emptied|secure|securely|no copies remain|no snapshots remain|nothing remains|small|has been destroyed|was destroyed|will be destroyed` (case-insensitive, word-bounded), and no `not yet` within 40 characters before a listed word; and zero occurrences of the volume id, a run id, `hooks`, `repos=`, `lock_residue` or any count. `destroy`, `destroyed` (only in the negated `has not been destroyed`), `deleted` are allowed. On INTERNAL RECORDS the negated phrases `not a scheduled job`, `does not say ... that they are gone` (regex `\b(does|do) not say\b[^.;]{0,160}\bthat (they|it) (are|is) gone\b`) and `neither says the residue is gone` are allowed verbatim and nothing else; the register is never grep-checked with the published list. Prove the grep can go red by running it once against a scratch copy that contains `scheduled for destruction`.
- [ ] AC3. T&C pointer: the canonical sentence occurs once in `docs/legal/terms-and-conditions.md` and the mirror sentence (link `/legal/data-protection-disclosure/`) once in the mirror, each as its own paragraph between the third 14.1b bullet and `If a Subscription is active`; the phrase `Section 10.3(b) of the` occurs exactly twice per T&C file (the pointer and the Last Updated entry); the three bullets and the closing Privacy Policy sentence have no removed word-diff chunk; `check-tc-document-sha.sh` passes (body equivalence, literal, seed parity and the posture-row replica).
- [ ] AC4. `substantiveChange` equals the Phase 3c label and matches `/^[§A-Z][^.]{9,}$/`; `TC_BUMP_METADATA.lastUpdated` equals the T&C Last Updated date; `TC_VERSION` reads `2.6.1` in `tc-version.ts`, both seed scripts and the `compliance-posture.md` T&C row, and `grep -rn "2\.6\.0" apps/web-platform/lib apps/web-platform/scripts apps/web-platform/test apps/web-platform/e2e knowledge-base/legal/compliance-posture.md` has no hit (do not grep the whole repo: `package-lock.json` and `.github/workflows/cla.yml` contain unrelated `2.6.0`). The pins themselves are enforced by Phase 6 gates, not re-asserted here.
- [ ] AC5. Dates and as-of: `Last Updated[: *]+<D>` (hero has no colon, body has `:**`) is identical on each document's canonical, mirror body and mirror hero; the previous entries are intact after `Previous:`; the Last Updated entries equal the CLO-ruled text (with CLO ruling B's two replacements); the as-of date in the bullet equals the UTC date of the Phase 1 reads recorded in `session-state.md`, not the edit day; no HOLD condition is true.
- [ ] AC6. Register: original PA-36 (f) and Status text unedited and followed by the Phase 4a/4b markers; M2 follows the ledger citation inside PA-36 (f); M1 follows the PA-2 (g) mention and each of the three PA-36 (g) mentions (each anchor asserted unique before insertion); the six `hcloud_volume.git_data` mentions that carry `2026-10-22` (one in PA-2 (g), three in PA-36 (g), two in PA-36 (f)) are each followed within about 450 characters by `Superseded <d>`; no digit of an existing `2026-10-22` was altered (compare the old string spans, not a total count: the markers themselves quote the date, so the file-wide count rises); no `Superseded <d>` within 300 characters after the `hcloud_volume.workspaces` hits (PA-1 (g), second PA-2 (g)) or the Inngest AOF hits; `last_reviewed` and the ledger JSON unchanged; each (f)/Status marker contains `fires on the merge of the draft PR` and `does not say` / `neither says the residue is gone`.
- [ ] AC7. Other records: ADR-239 diff is exactly the one blockquote; attestation 9066 diff is the frontmatter pointer plus one body blockquote and its frontmatter parses; `compliance-posture.md` diff is exactly the T&C row cells plus one new Active Items row.
- [ ] AC8. Scope: `git diff --stat origin/main...HEAD` lists only Files to Edit, Files to Create and pipeline-written files; `ADDED` of `docs/legal/privacy-policy.md`, `docs/legal/gdpr-policy.md`, their mirrors, `apps/web-platform/components/settings/delete-account-dialog.tsx` and `scripts/encryption-posture-ledger.json` returns nothing; the only removed word-diff chunks in the four legal docs are the DPD bullet's final period and the Last Updated openings.
- [ ] AC9. Every Phase 6 gate is green (including `technical-ruling-gate.sh --branch`, `lint-legal-scope-block-placement.sh` and the four vitest files).
- [ ] AC10. The CLO attestation file exists, is dated on the final-pin day, records DPD Tier 1 and T&C Tier 2 with the Tier 1 MINOR dissent, and covers the FINAL diff (a later byte change invalidates it until re-attested).
- [ ] AC11. PR #10528 is a draft with the DRAFT title prefix and banner, is not in the merge queue, has `Ref #10138` and `Ref #6897` and no `Closes`, `Fixes` or `Resolves`; its body carries the correction of the 2026-10-18 CLO record, the interim-not-discharged statement and re-open triggers, the unchanged-surface list, the operator rows, the Phase 1 read record, the sibling note and the account-count statement; no agent ran `gh pr ready`, `gh pr merge` or an enqueue; the plan carries the `## Operator Holds` section.
- [ ] AC12. No `gh workflow run` of `git-data-cutover.yml` or any wipe-family mode occurred (compare `gh run list --workflow git-data-cutover.yml` before and after); no comment or post on #10138, #6897, #9066, #9839 or any related issue; no Doppler write.

### Post-merge (owner-gated; not run by the pipeline)

- [ ] AC13. After the owner merges: `https://soleur.ai/legal/data-protection-disclosure/` and `https://soleur.ai/legal/terms-and-conditions/` contain the new sentences, and the banner's `fullTermsUrl` (`https://soleur.ai/pages/legal/terms-and-conditions.html`) resolves to the new text (the site deploy can lag the app deploy); `check-tc-document-sha` is green on `main`; the first `/accept-terms` load shows the new label. Run `soleur:postmerge` and emit DONE only after its literal line `postmerge verification complete!`.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Interim wording for DPD section 10.3(b) and the pointer in T&C section 14.1b, as a mirror-paired legal-docs PR" | Files to Edit 1-4; Phases 2, 3 | mapped |
| 2 | "(Ref #10138, Ref #6897 only; never Closes/Fixes/Resolves)" | AC11; Phase 7 | mapped |
| 3 | "Find the current section 10.3(b) in the DPD and section 14.1b in the T&C, including their mirror copies" | Research Reconciliation; Files to Edit 1-4 | mapped |
| 4 | "find the pair and the test/lint that enforces it, plus any Art. 30 marker / legal-doc SHA registry such as apps/web-platform/lib/legal/legal-doc-shas.ts that must stay consistent" | Phase 3 (pins), Phase 4 (register), Phase 6 (gates), Files to Edit 5-8 | mapped |
| 5 | "Read the CLO record on issue 6897 ... and search knowledge-base/ for the CLO ruling on residue wording" | Research Insights; decision-challenges.md | mapped |
| 6 | "Spawn soleur:legal:clo ... finish the truncated third sentence ... keep the three residue facts above" | Phase 2 text; decision-challenges.md | mapped |
| 7 | "VERIFY the 12 November 2026 destruction date against repo evidence ... before using it and flag it if unverifiable" | Research Reconciliation row 1; Phase 2 date wording | mapped |
| 8 | "no 'erased', 'purged' or 'deleted completely' wording; measured vs unmeasured claims must match the runbook evidence vocabulary" | AC2; claim-to-evidence table | mapped |
| 9 | "Record the CLO ruling in knowledge-base/project/specs/feat-one-shot-dpd-10-3b-interim-residue-wording/decision-challenges.md" | decision-challenges.md | mapped |
| 10 | "Mark the PR clearly as DRAFT legal wording requiring owner review before merge." | Phase 7; Operator Holds; AC11 | mapped |
| 11 | "never dispatch git-data-cutover.yml or any wipe/wipe_check workflow; agents do not post to the issues above or any related issue; never push or sync while the PR is in the merge queue" | AC12; Phase 0b; Pre-enqueue | mapped |
| 12 | "the Art. 30 marker and the T&C/DPD mirror must stay consistent" | Phase 4; AC6 | mapped |
| 13 | "flag the likely merge-conflict surface (SHA registry) in the plan but do not touch that PR" | Sibling PRs section | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| DPD files (Files to Edit 1-2) | "Interim wording for DPD section 10.3(b)" | asked |
| T&C files (Files to Edit 3-4) | "the pointer in T&C section 14.1b" | asked |
| `tc-version.ts` and `legal-doc-shas.ts` (5, 7) | "legal-doc SHA registry such as apps/web-platform/lib/legal/legal-doc-shas.ts that must stay consistent" | asked |
| Seed scripts (6) | - | inferred - `check-tc-document-sha.sh` Step 2.5 fails the required check, and QA users loop on `/accept-terms`, if the version moves without them |
| Register markers PA-36 (8) | "the Art. 30 marker and the T&C/DPD mirror must stay consistent" | asked |
| Census-keyed markers on `git_data` 2026-10-22 mentions (8) | - | inferred - CLO ruling: leaving a live-looking 2026-10-22 date for the same store beside the new 2026-11-12 sentence is a register-vs-published inconsistency |
| ADR-239 pointer (9) and attestation 9066 pointer (10) | - | inferred - CLO ruling: both carry a live-looking 2026-10-22 trigger already satisfied by ADR-239 Amendment 2026-10-12 |
| `compliance-posture.md` T&C row cells and follow-up row (11) | - | inferred - the T&C row is gate-forced (`check-tc-document-sha.sh` fifth replica); the follow-up row is a CLO round-2 ruling since the dialog, Privacy Policy and GDPR Policy are left unchanged |
| CLO attestation file (Create) | "Spawn soleur:legal:clo" and "VERIFY the 12 November 2026 destruction date against repo evidence" | asked |
| Pipeline stop rule | "Mark the PR clearly as DRAFT legal wording requiring owner review before merge." | asked |

### Split Assessment

- Subsystems touched: 4 - `docs`, `plugins/soleur`, `apps/web-platform`, `knowledge-base`
- Planned files: 11 edited + 3 created | Estimated changed lines: about 40 long-line edits, under 150 diff lines excluding pipeline files
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR. The four roots are one mirror-paired legal change plus its pins and records; splitting the register markers from the published text would leave the register contradicting the DPD between merges (the exact inconsistency this PR removes).

## Domain Review

**Domains relevant:** Legal, Product (advisory)

### Legal

**Status:** reviewed
**Assessment:** CLO agent (two spawns, 2026-10-19). Final wording, tiers, markers, census, forbidden-word mechanics, pre-merge read procedure, operator rows. Interim only; re-opens on any printed non-zero residue count, a flag or stamp set, 2026-11-12 passing with the volume present, a Hetzner copy measurement, or the gc-cursor decision.

### Product/UX Gate

**Tier:** none (mechanical UI-surface override did not fire: no `components/**`, `app/**/page.tsx`, `*.njk` or `*.html` file is created or edited; the only user-visible string is `TC_BUMP_METADATA.substantiveChange`, a copy change on an existing banner)
**Decision:** reviewed (CPO advisory)
**Agents invoked:** soleur:product:cpo, soleur:legal:clo
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings

CPO: SIGN-OFF WITH CONDITIONS. Re-acceptance impact LOW (roadmap beta-user count 1, a CLI-plugin tester; web-platform accounts are probably operator, test and synthetic only; not confirmed from the repo). Timing: merge outside any live tester session; do not hold the bump. Label: first-round label judged jargon, replaced by the CLO's plain-language label. Brand: honesty fits the brand; keep legal pages plain and declarative. Conditions and their disposition: (1) plain-language label - adopted (CLO label); (2) count real web-platform accounts before merge and avoid a live session - PR body statement and owner timing, AC11; (3) follow-up tracking so the interim text does not become permanent - existing trackers #10138 and #6897, ready-to-file text in the PR body, owner row; (4) pointer-only T&C paragraph - adopted; (5) owner review before merge - Operator Holds. CPO's suggestion to phrase the measuring gap as a committed action ("we will update this section") is declined: the CLO ruled that an unfulfilled promise would be false (decision-challenges `taste` row).

## User-Brand Impact

- **If this lands broken, the user experiences:** a person who asked for erasure reads "deleted" (or a destruction date stated as a schedule) and relies on it while identifier-bearing residue exists, or reads an interim notice stronger than the evidence ("erased", "clean", "scheduled") and is misled about what has and has not been done; or every user is bounced to `/accept-terms` with a confusing banner label.
- **If this leaks, the user's data is exposed via:** a published sentence that names a listing, a count, a run id or an account identifier from the volume (a public repository exposes run logs and this PR text); the plan and the published text state none, and AC2 bans them.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one person relying on an unqualified erasure statement is enough to damage the trust the product sells; `aggregate pattern` would understate a per-person Art. 17 reliance.

CPO sign-off at plan time: SIGN-OFF WITH CONDITIONS (recorded above). `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Sibling PRs and conflict surface (flagged; none touched)

Verified with `gh pr diff` on 2026-10-19:

- #10291 (draft, Better Stack SCC wording) edits `docs/legal/data-protection-disclosure.md`, its mirror and `legal-doc-shas.ts` at different sections; the shared surfaces are the one-line DPD `Last Updated` paragraph (both prepend) and the `"data-protection-disclosure"` hash line in `legal-doc-shas.ts` (the likely conflict).
- #9051 (draft, codex web) edits the DPD (a hunk in section 10.3 bullet `(d)`, two lines below our bullet `(b)` with one unchanged line between, so a textual merge is likely clean; plus other sections), `legal-doc-shas.ts` and Art. 30 register PAs elsewhere (not PA-36). Same Last Updated and hash conflicts.
- #8626 (draft, ledger root disks) rewrites PA-36 `(f) Retention` and `(g) TOMs` table rows and adds register convention bullets: a same-line conflict with our PA-36 (f) marker.

Rule: whichever PR merges second runs one `git merge origin/main`, keeps every Last Updated entry in date order, recomputes `legal-doc-shas.ts` (and `TC_DOCUMENT_SHA` if the T&C moved) from the merged canonical files with `sha256sum` (never take either side's literal), re-runs Phase 6, and has the CLO re-attest the merged diff. This PR must not edit those PRs' passages. Insertions into a line #8626 rewrites still conflict in git, and a clean merge is not safe either: our markers quote strings such as `Target: 2026-10-22, the ledger `expires_on`` that #8626 may change. After any merge touching the register, re-grep every quoted anchor and re-run AC6. A sibling that edits the T&C needs its own `TC_VERSION` re-check (neither #10291 nor #9051 edits the T&C today).

## Architecture Decision (ADR/C4) gate

Skipped: the change makes no architectural decision (no ownership boundary, substrate, trust boundary or ADR reversal); it qualifies published wording. The ADR-239 edit is a one-line stale-date pointer, not an amendment. C4: no actor, system, container or relationship changes (the T&C bump touches the existing web app and the Supabase `tc_acceptances` ledger only through existing behavior); `c4-count-parity` is unaffected because no count in `model.c4` moves.

## Gates Not Applicable (observability, encryption posture, IaC, guard)

Observability (plan Phase 2.9) skipped: the Files to Edit contain no file under `apps/*/server/`, `apps/*/src/`, `apps/*/infra/` or `plugins/*/scripts/` (the two seed scripts and `tc-version.ts` are under `apps/web-platform/scripts/` and `lib/legal/`), and no new infrastructure surface is introduced. Encryption posture (Phase 2.11), IaC routing (2.8) and Guard Contract (2.12): skipped, no store, connection, infrastructure or new guard is introduced.

## Test Scenarios

- Given the Phase 2 edit with the DPD pin not yet refreshed, `check-tc-document-sha.sh` fails on the stale `data-protection-disclosure` literal and passes after the re-pin.
- Given the T&C pointer without the `TC_VERSION` bump, the guard fails "literal is stale and TC_VERSION was not bumped"; given the bump without the seed scripts or the posture-row version, Step 2.5 and the fifth-replica check fail.
- Given a `substantiveChange` containing a period, `accept-terms-copy-regression.test.tsx` fails.
- Given a scratch copy of the DPD bullet containing "scheduled for destruction" or "erased", the AC2 grep returns a hit (proof the grep can go red).
- Given a flag read of `true` or a non-zero read exit, Phase 1 records a HOLD and no later phase runs.

## Risks and Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6. This plan fills it.
- The CLO's round-2 operator-row category for publishing the date was "legal-risk" with a note that the default is not to publish; round 1 (full context) advised against a dateless version and treated it as a schedule statement. The row records the owner's decision either way; the owner may delete the date clause, in which case the CLO's dissent (a dateless notice is worse for Art. 13(2)(a)) applies and the claim-to-evidence row for the date, AC1's "12 November 2026" count and the register markers must be edited together.
- The as-of date goes stale: the CLO's rule is that it must be the merge day or the day before at enqueue. A stale as-of date is refreshed by a DPD/register-only push BEFORE the owner enqueues; never while queued.
- The DPD bullet contains the original sentence twice by design (live prefix and the `*(Amended ...)*` quotation). A "replace once" script or a file-wide count will mis-handle it; use the AC1 line-scoped count.
- `grep -c` counts lines, not occurrences; on these single-line bullets and cells use `grep -o | wc -l` or the `python3 -I` span check.
- The `ADDED` word-diff filter needs `--word-diff=porcelain`; a whole-line diff returns every pre-existing token on the 1 to 70 KB lines.
- ADR-239's `**Target: 2026-10-22**,` sits inside an indented multi-line list item; place the blockquote pointer after that whole bullet and run markdownlint.
- Registers: three `tracking_issue: "#6897"` ledger rows (`workspaces`, `git_data`, rehearsal) share the issue; a census keyed on the issue number mislabels `hcloud_volume.workspaces` cells. Key on the store name.
- `TC_VERSION` is mirrored in two shell scripts; a bump that misses them reds a required check only in CI.
- Do not quote private chat or attribute any comment by account name in committed files or the PR body (learning 2026-10-18). Do not name the `hooks` directory, a run's counts, or any listing in the published text.
- The T&C bump closes live WebSocket sessions on the next gated message (unsaved input and in-flight agent runs are dropped) and redirects every browser client, not the CLI plugin; a user who declines stays gated (existing behavior). The owner times the merge outside a live tester session; the PR body states this in plain words.
- Banner label vs bullet: the label says "retired storage" while the bullet also covers a marker on other storage, and users who never deleted anything see it; the CLO chose the label, and the owner may soften it at review (taste).
- The published passage gives a data subject no route to ask which accounts are affected; the existing rights and contact sections stand (CLO ruled no new contact promise). Flagged for the 2026-10-24 re-ruling.
- Phase 3c/3e pins are provisional; Phase 5 sets the final values after the last wording edit and the last `git merge origin/main`.
- Unverifiable here: the number of real web-platform accounts that will be redirected (CPO), the Hetzner copy-retention state (a CTO read of the images API would narrow it; out of scope and not run), and whether the volume still exists at merge (Phase 1 re-reads it).

## Alternative Approaches Considered

| Alternative | Rejected because |
|---|---|
| Keep the original sentence verbatim and append a separate caveat sentence | A reader who stops after sentence one leaves with an unqualified "deleted" (CLO) |
| Rewrite "deleted" more heavily | Nothing in the evidence shows the content claim is false; the residue is identifiers, not API keys or workspace content (CLO) |
| "Scheduled for destruction by 12 November 2026" (the surviving fragment) | No job exists; the destroy needs an owner dispatch; a missed public commitment becomes a published falsehood (CLO) |
| Leave T&C 14.1b unedited (no version bump) | The T&C would keep an unqualified "are deleted from Hetzner" beside a qualified DPD (CLO); declining the bump is a legal-risk acceptance the CLO will not rule as Tier 3 |
| Tier 3 pointer, re-pin only | The pointer qualifies a stated outcome; the bump policy says treat doubt as clarifying |
| Register-only provider-copy clause | The destruction sentence invites reading destruction as the end of the data; Art. 13(2)(a) readers look in the DPD (CLO dissent noted: defensible if a shorter notice is preferred) |
| Edit the Delete Account dialog, Privacy Policy and GDPR Policy in this PR | Code/UI scope and a wider legal diff than the brief; CLO ruled follow-ups (dialog before any flip, PP and GDPR at the 2026-10-24 re-ruling) |

## Deferral Tracking

Deferred items and their trackers: the full 2026-10-24 CLO re-ruling and the Privacy Policy section 7 and GDPR Policy section 8.4 cross-references - tracked on #10138 item 3 (open, priority p1); the Delete Account dialog copy before any flip and the wipe/flip chain - tracked on #6897; the Hetzner snapshot/backup retention measurement (a CTO read of the Hetzner images API) - inherited open item of attestation 9066, tracked on #6897/#9066; the `.gc-cursor` payload fix - #9066. This PR creates no new issue and posts nothing; the PR body carries ready-to-file text for the owner (decision-challenges `operator (scope)` row).
