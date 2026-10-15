---
title: "chore: flip ADR-282 adopting to accepted (and the sister records)"
date: 2026-10-15
slug: flip-adr-282-adopting-to-accepted
branch: feat-one-shot-10018-adr-282-adopting-to-accepted
issue: 10018
type: chore
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

## Overview

ADR-282 (delete protection plus `prevent_destroy` on the sole-copy Inngest LUKS volume `hcloud_volume.inngest_redis_luks`,
Hetzner id 106903269) names its own flip condition: the post-apply read-back (runbook
`knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md` section 5c step 3) must return the expected
word `protected`. It did, on 2026-10-15 (UTC). This plan records that evidence once, in an ADR-282 addendum, flips ADR-282's
frontmatter status, and brings every record that mirrors the "adopting" wording up to date by the form that record's own
convention allows. It is one docs-only PR, referencing #10018 only (no closing keyword anywhere).

Spec file: none was created by brainstorm; `lane:` defaulted to `cross-domain` (fail-closed) because no spec carries one.

Issue #10018 body (the producer's own list, a floor not a ceiling): "ADR-282, runbook inngest-luks-cutover-6894.md section
5c, the ADR-119, ADR-142 and ADR-263 addenda, the C4 model, the Art. 30 register, compliance-posture and the
encryption-posture ledger". The repo-wide subject sweep below adds ADR-199 and two further runbook sentences.

## Enhancement Summary

**Deepened on:** 2026-10-15
**Sections enhanced:** gate verification (4.4-4.12), citation re-verification, one added section (Encryption Posture), one added note (Network-Outage)
**Agents used:** CTO (technical rulings T1-T8), CLO (legal rulings L1-L3), plan-review panel (DHH, Kieran, code-simplicity); no further research fan-out was warranted for a docs-only status flip with every claim already traced to a repo file or a GitHub run log.

### Key improvements

1. Vacuous check removed: AC-4's wrapped-line phrase ("takes" / "effect" split across runbook lines 330-331) could never have failed; the pattern now starts on the second line and is first run against `origin/main`.
2. Run history stated exactly: merge-SHA run 38139392390 applied the update and later failed on an unrelated step; the brief's "all succeeded" is not repeated.
3. Legal wording is the CLO's verbatim text; non-legal markers shortened to a pointer so the run facts live once, in the ADR-282 addendum.

### New considerations discovered

- ADR-199 carries an `adopting` sentence about ADR-282 that the issue's list missed.
- `model.likec4.json` holds the C4 sentence in 3 description strings (5 matching lines); the regenerated diff must show exactly those.
- Compliance-posture's row ends in `**]**`: the appended marker needs a separating space or the result is `]****]`.

## Gate Notes (deepen-plan 4.4-4.12)

- 4.5 Network-Outage: the word "timeout" appears only as a quoted fact of an unrelated, past job step (`terraform_data.egress_gateway_web2` remote-exec). The plan proposes no SSH, firewall or service-layer fix and drives no `terraform apply`, so the L3-first checklist has nothing to verify; no apply provisioner is in scope.
- 4.55 Downtime: none (docs only, no infra path, no apply triggered).
- 4.6 User-Brand Impact: present, threshold `aggregate pattern`, non-placeholder.
- 4.7 Observability: skipped (every Files-to-Edit path is a record, a generated JSON twin or the ledger JSON; no code or infra path).
- 4.8 PAT-shaped variables: grep over the plan returns nothing.
- 4.9 UI wireframe: skipped (no UI-surface file).
- 4.11 Guard Contract: skipped (no guard delivered; AC-6 is a one-time sweep, not a standing gate).
- 4.12 Scope Check: one unfenced `## Scope Check`, three subsections, no `unmapped`, no empty justification, a `Recommendation:` line, no `status: BLOCKED`.
- Citations re-verified live with `gh`: #9925, #9876, #10083, #10014, #10103 MERGED; #9879 and #9372 CLOSED; #9927, #9703, #9705, #10112 OPEN; #10081 an OPEN PR labelled `parked`. No AGENTS rule ID is cited in the plan body.

## Encryption Posture

No new store or connection is introduced; this section records that the existing ledger row is not changed in substance (4.10 trigger fired on prose naming a volume).

```yaml
at_rest:
  - store: hcloud_volume.inngest_redis_luks (existing ledger row; unchanged by this PR)
    mechanism: luks
    evidence: scripts/encryption-posture-ledger.json row hcloud_volume.inngest_redis_luks, at_rest.evidence (cloud-init-inngest.yml luksFormat/luksOpen, inngest-redis-luks.tf)
    defends_against: a seized, RMA'd or snapshot-imaged Hetzner block volume
    does_not_defend: a leaked credential, an app-layer read on the unlocked host, a dead probe pipeline, a read/write Hetzner token holder lifting delete protection, loss of both passphrase copies, and the absence of any backup of the ciphertext or header (all carried unchanged in the row)
    disclosed_as: not-publicly-claimed
    live_verification: unavailable:the hourly probe row proves which device backs /mnt/data, not the cipher (unchanged; this read-back is not the ledger's live verification)
in_transit: []   # no connection added or changed
```

## Research Reconciliation - Spec vs. Codebase

| Claim in the brief or issue | Reality (measured this session) | Plan response |
|---|---|---|
| "Recent apply-web-platform-infra.yml runs on main all succeeded (latest 38653889114 on 944372f0d5)" | True for the latest (success, 2026-10-14T23:24:33Z, push). Not all of the 15 most recent were green: dispatch run 38580429629 failed (2026-10-14T14:25:47Z). The merge-SHA run 38139392390 (67cb281e4f) ALSO concluded `failure`. | Record the run facts exactly as measured; never write "all succeeded". |
| Issue: "apply run 38139392390 changed hcloud_volume.inngest_redis_luks delete_protection from false to true" | The log shows "will be updated in-place ... delete_protection = false -> true" and "Apply complete! Resources: 0 added, 1 changed, 0 destroyed" at 2026-10-11T12:32:53Z; the job then failed at 12:48:18Z on an unrelated later step (`terraform_data.egress_gateway_web2` remote-exec, dial tcp i/o timeout). | Addendum states both facts (CTO ruling T1, CLO limit 4). The read-back is the arbiter, as the runbook already says. |
| Brief: read-back timestamp | Only the date (2026-10-15, UTC) was captured; no time-of-day. | Record date-only; do not invent an hour (CTO ruling T2). |
| Issue lists 8 files / 36 lines | The subject sweep finds 11 files (adds ADR-199 and the model.likec4.json generated twin; the runbook has three stale spots, not one). Size is larger than the producer's estimate. | Plan covers the full sweep; PR body states ADR-199 was added beyond the issue list. |
| Postmerge Phase 5.7 step 6 files the flip issue "only while ADR-282 is adopting" | It goes inert by itself after the flip. Phase 5.7 is path-triggered on `apps/web-platform/infra/inngest-redis-luks.tf`, which this PR does not touch, so post-merge records `Sole-copy read-back: SKIPPED (no triggering paths)` and makes no Hetzner call. | Leave `plugins/soleur/skills/postmerge/SKILL.md` unedited (also required by Guard 1 row H2, byte-identity with the runbook one-liner). |

## Research Insights

### Premise validation

Checked: #10018 is OPEN (labels `priority/p3-low`, `type/chore`, `domain/engineering`); PR #9925 is MERGED
(commit `67cb281e4f`, an ancestor of `origin/main`); `git show origin/main:apps/web-platform/infra/inngest-redis-luks.tf`
carries `delete_protection = true` inside `resource "hcloud_volume" "inngest_redis_luks"` (and `prevent_destroy = true` on the
pair, the volume and the two Doppler cascade parents); PR #10081 is an OPEN draft labelled `parked` with no auto-merge
armed; #9927 (deferred key-loss residuals) is OPEN; the ADR corpus (ADR-282 `## Status`, #9876 and #10083 precedents) states
the flip convention, so the mechanism is not a rejected alternative. All held; the only stale premise is the "all succeeded"
phrasing above.

### Property List (what the PR must buy)

1. A reader of ADR-282 sees `status: accepted` and the dated evidence (word, date, volume id, derivation, run ids).
2. No record still tells a reader that a verified protection on user data is a plan, or "do not assume it exists".
3. History is not rewritten: stale 2026-10-10 sentences in append-only records stay as dated record, superseded by a marker.
4. No sister cell claims more than was measured (point-in-time flag read; `prevent_destroy` not read live; residuals and the
   absent Art. 32(1)(c) capability unchanged).
5. Existing guards stay green (Guard 1 H1b/H2, C4 gates, ledger lint, legal-register lint, ADR ordinal check).

### Cut List (mechanisms not adopted)

| Mechanism | Property | What covers it / why cut |
|---|---|---|
| Edit `plugins/soleur/skills/postmerge/SKILL.md` to retire step 6 | none new | Step 6 gates on `status: adopting`; inert after the flip. Editing breaks the byte-identity row. |
| New counsel-record file under `knowledge-base/legal/audits/` | none | CLO L3: no falsified claim is corrected, nothing attests. Destruction records are out of bounds. |
| Re-run the Hetzner read-back | none | Evidence is the single read-back already taken; the brief forbids further production calls. |
| A new followthrough or soak enrollment | none | No time-gated close criterion; the flip condition was already met. |
| A guard asserting the "no stale adopting" state | 2 | A one-time status correction; the residual sweep is an acceptance check, not a standing gate (YAGNI). |

### Repo-wide subject sweep (every hit read)

Grep keys: `adopting` (phrase) AND the subject nouns `ADR-282`, `9925`, `inngest_redis_luks`, `106903269`,
`INNGEST_REDIS_LUKS_KEY`, `sole-copy`, `delete_protection`, `unprotected`, "in force only once", "takes effect on the merge".
Archived plans, specs, learnings and counsel/destruction records are point-in-time records and excluded.

| # | File | Stale wording (anchor) | Disposition |
|---|---|---|---|
| 1 | `knowledge-base/engineering/architecture/decisions/ADR-282-sole-copy-luks-volume-protection-set.md` | frontmatter `status: adopting`; `## Status` "**Adopting - 2026-10-10 (#9879, PR #9925).**" ... "Until then every sentence below that says a protection 'is in force' is a plan, not a fact" | Frontmatter flip; leading dated blockquote above the Status prose; Addendum at end carrying the evidence. History prose kept. |
| 2 | `.../ADR-119-luks-at-rest-for-the-live-workspaces-volume.md` | addendum 2026-10-10 last sentence "(adopting until that merge's apply and read-back, per ADR-282)" | Append dated supersession blockquote. Frontmatter already `accepted`. |
| 3 | `.../ADR-142-inngest-redis-aof-zero-data-loss-luks-migration.md` | addendum 2026-10-10 "**Status of this addendum: adopting.** It becomes true of the live store when PR #9925 is merged ... Until then each mark below describes the target state" | Append dated blockquote directly under that paragraph. Frontmatter already `accepted`. |
| 4 | `.../ADR-263-guest-side-fresh-boot-luks-for-web-hosts.md` | addendum 2026-10-10 last sentence "(adopting until that merge's apply and read-back, per ADR-282)" | Append dated blockquote. Frontmatter already `accepted`. |
| 5 | `.../ADR-199-destructive-clearance-requires-a-measured-empty-store-and-a-dark-host.md` | addendum 2026-10-14 "conditional on ADR-282, whose status is `adopting` as read when this was written" | NOT in the issue list; found by the subject sweep. Time-stamped, so true as history, but a reader of that sentence alone draws the wrong conclusion: append dated blockquote. Frontmatter already `accepted`. |
| 6 | `knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md` | three spots: the paragraph at "The live LUKS volume ... is now the only copy" ("it is in force only once that PR is merged ... so do not assume it exists before then"); "Rules that stay in force" bullet ("takes effect on the merge of PR #9925 and its apply"); section 5c "**Status: adopting (#9879, PR #9925, ADR-282).**" + "Until then treat the live volume as unprotected (as §5a said)" | Living operational doc: rewrite the three spots in place (CTO T4). Read-back one-liner and heading text stay byte-stable. |
| 7 | `knowledge-base/engineering/architecture/diagrams/model.c4` (Inngest container description) and generated `model.likec4.json` | "PROTECTION (#9879, ADR-282; conditional: in force only once PR #9925 is merged ... and the ADR status flips from adopting to accepted in the follow-up commit that the post-merge read-back step triggers, owned by the PR's author)" | In-place edit of that parenthetical; regenerate the JSON with the repo script, never by hand (CTO T5). |
| 8 | `knowledge-base/legal/article-30-register.md` PA-13 (g) TOMs item (13) | heading "(#9879, ADR-282; adopting: in force only once PR #9925 is merged, its apply has landed and the post-apply read-back passes)" | CLO L2: minimal in-cell edit of the parenthetical + appended dated marker quoting the old qualifier verbatim. No `last_reviewed` bump. |
| 9 | `knowledge-base/legal/compliance-posture.md` row "Plaintext Inngest Redis AOF backstop volume destroyed" | bracket "[2026-10-10 (#9879, ADR-282): ... On the merge of PR #9925 and its apply (adopting until the post-apply read-back passes) ..." | CLO L2: appended dated marker inside the row before the closing `**]**`; do not rewrite the bracket. `last_updated` bump + one-line header comment (optional, recommended). |
| 10 | `scripts/encryption-posture-ledger.json` row `hcloud_volume.inngest_redis_luks`, `does_not_defend` | "are declared in Terraform by #9879 (ADR-282) and take effect on the merge of PR #9925 and its apply;" | CLO L2: one minimal in-place replacement; `mechanism` and `live_verification` untouched. |

Read and left unchanged, with reason: `plugins/soleur/skills/postmerge/SKILL.md` (procedure, gates itself off, byte-identity
row); `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md` (a "Superseded 2026-10-10"
blockquote about the HALT, not about adopting); `plugins/soleur/test/terraform-target-parity.test.ts`,
`tests/scripts/test-infra-privileged-tier-census.sh`, `apps/web-platform/infra/*` (comments cite ADR-282 as a reason, no status
claim; infra paths are off-limits here anyway); `knowledge-base/legal/audits/*` (counsel reviews and the two destruction
records are attestation-class; NOT touched); `nfr-register.md` (its "Adopting" cells are ADR-068, a different subject);
other `adopting` hits repo-wide (ADR-239, ADR-276, ADR-241 D1, the zot and git-data followthroughs, skills) are other subjects.

### Institutional learnings applied

- `2026-10-12-a-record-pr-for-an-arm-must-sweep-the-claim-and-pin-the-runtime-value.md`: a stale-claim sweep is indexed by the
  claim's subject (repo-wide grep), not the plan's file list; this plan's ten-row table is the result.
- `2026-09-27-a-status-flip-sweep-must-include-the-legal-registers-that-state-the-mechanism.md`: a status flip sweeps
  `knowledge-base/legal/` and routes hits to the CLO for append-only wording (done: CLO L1-L3).
- Precedents #9876 (ADR-270/276: "frontmatter status is the only in-place edit per file"), #10083 (ADR-263 accepted: dated
  blockquotes, runbook marks, C4 sentence edits plus regenerated JSON), #10014 (legal supersession markers).

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly; the failure mode is a record that misstates how well the
store holding their queued reminders and in-flight job payloads is protected, either by still calling a verified protection
a plan (a reader discounts it) or by over-claiming it (a reader believes protection is continuous or covers key loss).
**If this leaks, the user's data is exposed via:** no new exposure vector; the PR adds a volume id and run ids that are already
public in the repo, no secret, token value or passphrase.
**Brand-survival threshold:** aggregate pattern - the correction narrows claims to one dated, point-in-time measurement and
carries every residual forward unchanged. (The ADR-282 subject is `single-user incident`; this PR changes no control, so no
per-PR CPO sign-off is added.)

Sensitive-path note: the diff touches no path in the preflight `SENSITIVE_PATH_RE` (no `apps/*/infra/`, no
`apps/web-platform/server|supabase|app/api`, no workflow); `knowledge-base/legal/*` and `scripts/encryption-posture-ledger.json`
are outside it, so `threshold: none` scope-out text is not required.

## Open Code-Review Overlap

Queried open `code-review` issues against every planned file. Two bodies mention planned paths:

- #9705 (dead-probe heartbeat for the inngest wrong-volume alert; touches `model.c4`): **Acknowledge** - the heartbeat was armed
  by #9703 on 2026-10-12 and this PR does not touch that sentence; the scope-out stays open.
- #10112 (finish the #9786 residuals once #10081 lands; mentions the encryption-posture ledger): **Acknowledge** - different
  concern, gated on parked #10081; this PR edits one unrelated clause of the ledger.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "flip ADR-282 and its sister records from \"adopting\" to \"accepted\"" [brief] | Phases 1-4 | mapped |
| 2 | "Own PR, \"Ref #10018\" only (no closing keyword in body, title or commits; assert closingIssuesReferences is [] after every body edit)" [brief] | Phase 5 steps 2-3, AC-8 | mapped |
| 3 | "find every record that says \"adopting\" for this protection ... by grepping the SUBJECT repo-wide, not just the phrase, and read each hit" [brief] | Research Insights sweep table, AC-6 | mapped |
| 4 | "follow the ADR append-only convention (add a dated addendum recording the read-back instead of rewriting history; flip Status lines only where the convention allows)" [brief] | Phase 1 | mapped |
| 5 | "Record the evidence (word, timestamp, volume id, expected-word derivation) in the ADR addendum; no secrets" [brief] | Phase 1 step 3 | mapped (timestamp is date-only: none was captured) |
| 6 | "do not touch knowledge-base/legal/audits/*destruction-record.md" [brief] | AC-9 | mapped |
| 7 | "take full ownership, including queueing auto-merge once required CI is green, then post-merge verification" [brief] | Phases 5-6 | mapped |
| 8 | "Report the #10081 park/no-replace status at the end." [brief] | Phase 6 step 4 | mapped |
| 9 | "Locally run only targeted or TEST_GROUP=affected suites" [brief] | Phase 4 | mapped |

### Plan-Item Provenance

| Plan item | User words cited | Verdict |
|---|---|---|
| ADR-199 marker | "grepping the SUBJECT repo-wide, not just the phrase" | asked (found by the sweep) |
| Two extra runbook sentences | "runbook §5c Status paragraph and any \"until then treat as unprotected\" text" | asked |
| Regenerating `model.likec4.json` | "the C4 model" (issue body) | asked (the JSON is the generated twin of model.c4, committed) |

### Split Assessment

- Subsystems touched: 3 - `knowledge-base/engineering/` (ADRs, runbook, C4), `knowledge-base/legal/`, `scripts/` (one JSON)
- Planned files: 12 (ten records, the generated JSON, and the plan artifacts) | Estimated changed lines: about 120 (the generated JSON diff is a handful of lines)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines - none met
- Recommendation: single PR (CTO T6: a split leaves contradictory records on main between merges)

## Architecture Decision (ADR/C4)

No new architectural decision: this PR changes a status and the tense of existing statements. The decision itself (the pin set)
is unchanged.

### ADR

Amend ADR-282 (frontmatter status, leading blockquote, addendum) and append supersession markers to ADR-119, ADR-142, ADR-263
and ADR-199, through the convention rather than `soleur:architecture create` (no new ordinal; the ordinal check
`scripts/check-adr-ordinals.sh` still runs).

### C4 views

Container view content changes by one sentence in the Inngest container description only. Enumeration against all three model
files (`model.c4`, `views.c4`, `spec.c4`), none of which gains or loses an element or edge: (a) external human actors - none
added or removed; (b) external systems/vendors - Hetzner and Doppler already modeled; (c) containers/data stores - the Inngest
store container is the edited element; (d) actor-surface access relationships - unchanged. `views.c4` needs no `include` change.
The derived cardinalities embedded in edge prose are untouched, but `plugins/soleur/test/c4-count-parity.test.sh` is run anyway.

### Sequencing

Single PR; the ADR is true now (the condition was met on 2026-10-15), so nothing is staged behind a soak.

## Domain Review

**Domains relevant:** Engineering (CTO), Legal (CLO)

### Engineering

**Status:** reviewed
**Assessment:** Ruled by CTO agent, 2026-10-15 (rows T1-T8 in `knowledge-base/project/specs/feat-one-shot-10018-adr-282-adopting-to-accepted/decision-challenges.md`): evidence sufficient; ADR form; sister addenda incl. ADR-199; runbook in place; C4 and ledger in place; one PR; postmerge SKILL untouched.

### Legal

**Status:** reviewed
**Assessment:** Ruled by CLO agent, 2026-10-15 (rows L1-L3): past-tense dated point-in-time wording; Article 30 heading edit + marker; compliance-posture marker only; ledger minimal in-place edit; no posture change, no counsel record, no `last_reviewed` bump. The CLO issues a DISCHARGED or BLOCKED verdict on the final diff text; work requests it before ship.

Product/UX Gate: not relevant (no user-facing surface; no `components/**`, `app/**` file). Pencil: N/A (no UI surface).

## Infrastructure, Observability, Guard Contract

Skipped by their own rules: no infra file, no code-class file, no guard delivered (Encryption Posture is recorded above because the 4.10 prose trigger fired). The ledger row's
`mechanism` (`luks`), `live_verification` and `at_rest` evidence are not edited; only one `does_not_defend` clause is.

## Files to Edit

1. `knowledge-base/engineering/architecture/decisions/ADR-282-sole-copy-luks-volume-protection-set.md`
2. `knowledge-base/engineering/architecture/decisions/ADR-119-luks-at-rest-for-the-live-workspaces-volume.md`
3. `knowledge-base/engineering/architecture/decisions/ADR-142-inngest-redis-aof-zero-data-loss-luks-migration.md`
4. `knowledge-base/engineering/architecture/decisions/ADR-263-guest-side-fresh-boot-luks-for-web-hosts.md`
5. `knowledge-base/engineering/architecture/decisions/ADR-199-destructive-clearance-requires-a-measured-empty-store-and-a-dark-host.md`
6. `knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md`
7. `knowledge-base/engineering/architecture/diagrams/model.c4`
8. `knowledge-base/engineering/architecture/diagrams/model.likec4.json` (generated by `bash scripts/regenerate-c4-model.sh`; also re-staged by the lefthook `c4-model-regenerate` hook; never hand-edited)
9. `knowledge-base/legal/article-30-register.md`
10. `knowledge-base/legal/compliance-posture.md`
11. `scripts/encryption-posture-ledger.json`

Pipeline-written files the diff-scope AC must allow: this plan, `knowledge-base/project/specs/feat-one-shot-10018-adr-282-adopting-to-accepted/{tasks.md,decision-challenges.md,session-state.md}`, and the generated `knowledge-base/INDEX.md` if the pipeline regenerates it.

## Files to Create

None (the addendum is a section in ADR-282; no new learning file is prescribed - compound decides).

## Implementation Phases

Every date is 2026-10-15 (UTC). Tense rule (decision row X1): no cell asserts continuous protection; each says the volume update
was applied by the PR #9925 merge apply (run 38139392390, 2026-10-11) and the delete-protection flag was read back as `protected`
on 2026-10-15; non-legal records (ADR-119/142/263/199 markers, runbook, C4) carry only "ADR-282 accepted 2026-10-15; evidence in its addendum" and need not restate run ids (they live once, in the ADR-282 addendum); the CLO-approved legal markers and the ledger clause keep their full wording. Never "green" or "successful" for run 38139392390. No time-of-day.

### Phase 0 - Re-verify and re-sweep (work start)

1. `git fetch origin main`; confirm the cited HCL is unchanged: `git show origin/main:apps/web-platform/infra/inngest-redis-luks.tf | grep -n "delete_protection"` still shows `delete_protection = true` at the volume.
2. Re-run the subject sweep (the grep keys in Research Insights) over non-archived paths and diff against the ten-row table; any new hit is read and dispositioned before Phase 1 (main moves under a long session).
3. No Hetzner, Doppler or production call. `gh` (GitHub) reads are fine.

### Phase 1 - ADR-282 and the sister addenda

1. ADR-282 frontmatter line 3: `status: adopting` -> `status: accepted`. No other frontmatter edit.
2. Insert directly under `## Status` (above the "**Adopting - 2026-10-10 ...**" paragraph), leaving that paragraph untouched:

   > **Accepted 2026-10-15 (#10018).** The condition stated below was met: the post-apply read-back (runbook section 5c, step 3) returned `protected` for volume 106903269 on 2026-10-15 (UTC), the word derived from `origin/main`. The evidence is in the Addendum of that date at the end of this ADR. The paragraph below is the 2026-10-10 text, kept as history: its sentence "Until then every sentence below that says a protection 'is in force' is a plan, not a fact" describes the state before the read-back, and the follow-up PR it promises ("the flip itself is one follow-up PR") is this one.

3. Append at the end (after the 2026-10-14 addendum) `## Addendum — 2026-10-15 (#10018, accepted: the read-back)` (em dash, as in the file's existing `## Addendum — 2026-10-14 (#8316)`). Content (no secret, no token value):
   - "Appended; nothing above is changed except the frontmatter status and the leading blockquote under Status."
   - Evidence in three or four lines of prose: the read-back word `protected` (exit 0) for Hetzner volume 106903269 (`hcloud_volume.inngest_redis_luks`) on 2026-10-15 (UTC; no time-of-day was captured), read-only, by the runbook section 5c step 3 one-liner (cited by section, not reprinted); the expected word `protected`, derived from `origin/main` `apps/web-platform/infra/inngest-redis-luks.tf`, `delete_protection = true` inside `resource "hcloud_volume" "inngest_redis_luks"`, delivered by #9925 (commit `67cb281e4f`, an ancestor of `origin/main`); the two words match.
   - Run facts, verbatim from the CTO ruling T1: "Merge-SHA apply run 38139392390 applied the in-place update `hcloud_volume.inngest_redis_luks delete_protection false -> true` ('Apply complete! Resources: 0 added, 1 changed, 0 destroyed', 2026-10-11T12:32:53Z); the job's conclusion was later `failure` (12:48:18Z) on an unrelated step (`terraform_data.egress_gateway_web2` remote-exec, dial tcp i/o timeout) after that apply had completed. The latest apply on main, run 38653889114 on 944372f0d5, succeeded. Later successful runs are consistent with the read-back; only the read-back proves the flag."
   - What the read-back is and is not: a point-in-time read of the delete-protection flag only; `prevent_destroy` is a plan-time control, enforced by the guards named in this ADR, and is not read back from any live system; Guard 1 stays advisory until #9927; the residuals, the loss-mode table, the absent Art. 32(1)(c) restore capability and the "no sanctioned erase path" statement are unchanged.
   - "Who flips it" is discharged by this follow-up PR; `soleur:postmerge` Phase 5.7 step 6 files no issue once the status is `accepted`.
4. Sister markers, appended directly under the stale sentence (blockquote, history untouched, frontmatter untouched):
   - ADR-119: after the last sentence of the 2026-10-10 addendum.
   - ADR-142: directly under the "**Status of this addendum: adopting.**" paragraph.
   - ADR-263: after the last sentence of the 2026-10-10 divergence-note addendum.
   - ADR-199: after the paragraph containing "whose status is `adopting` as read when this was written".

   Marker text (same in all four):

   > **Superseded 2026-10-15 (#10018), as to "adopting":** ADR-282 is `accepted` (its post-apply read-back returned `protected` on 2026-10-15; evidence in ADR-282's addendum of that date). The sentence above is kept as the dated record.

   (Run facts and limits live once, in the ADR-282 addendum; the CLO-approved legal markers below keep their own full wording.)

### Phase 2 - Runbook (in place; living document)

Edit only these three spots; keep the heading text "Sole-copy protection and key loss" and the whole section 5c read-back
one-liner (and its surrounding fence) byte-identical:

1. The paragraph ending "... described in §5c; it is in force only once that PR is merged, its apply has landed and the §5c read-back returns `protected`, so do not assume it exists before then." -> "Protection for that (delete protection, edge pins, key-loss posture) was built by #9879 (PR #9925, ADR-282, accepted 2026-10-15) and is described in §5c." (drop the conditional clause; the evidence is in the ADR addendum and §5c). The original is line-wrapped ("is built by" / "#9879 ..."); match across the wrap with a multi-line `Edit` string. "is built by" -> "was built by" is intended.
2. The "Rules that stay in force" bullet (the sentence wraps across two lines: `takes` ends one and `effect on the merge of PR #9925 and its apply)` starts the next): "protection is described in §5c and ADR-282 and takes effect on the merge of PR #9925 and its apply" -> "protection is described in §5c and ADR-282 (accepted 2026-10-15)".
3. Section 5c status paragraph -> `**Status: accepted 2026-10-15 (#10018, ADR-282).** The read-back below returned protected on 2026-10-15 (evidence: ADR-282, Addendum 2026-10-15). It is a point-in-time check of the delete-protection flag; re-run it after any infra-path merge and after a sanctioned lift (each step below says what it expects).` Delete "Until then treat the live volume as unprotected (as §5a said)". Keep the later "unprotected window is a stated cost" sentences in the break-glass route (a different, future state).

### Phase 3 - C4 and ledger (current-state descriptions, edited in place)

1. `model.c4` Inngest container description: replace only the parenthetical after "PROTECTION" with "(#9879, ADR-282 accepted 2026-10-15)". Leave the rest of the description (RESIDUALS onward) byte-identical. Then `bash scripts/regenerate-c4-model.sh` and commit the regenerated `model.likec4.json` (never hand-edit; the `c4-model-freshness` test gates it). The JSON carries the string in several places (5 matches before the edit); the diff must touch only those description strings.
2. `scripts/encryption-posture-ledger.json`, row `hcloud_volume.inngest_redis_luks`, `does_not_defend`: replace exactly "are declared in Terraform by #9879 (ADR-282) and take effect on the merge of PR #9925 and its apply;" with "were declared in Terraform by #9879 (ADR-282) and merged in PR #9925 (2026-10-11); the Hetzner delete-protection flag was read back as `protected` on 2026-10-15 (point-in-time; `prevent_destroy` is a plan-time control and is not read back);". The wording is the CLO's (L2) and stays verbatim. Everything else in the string, `mechanism` (`luks`) and `live_verification` (`unavailable:...`) stay byte-identical. The resulting sentence must read: "... Hetzner delete protection on the volume and prevent_destroy on the volume, the passphrase pair and the two Doppler cascade parents were declared in Terraform by #9879 (ADR-282) and merged in PR #9925 (2026-10-11); the Hetzner delete-protection flag was read back as `protected` on 2026-10-15 (point-in-time; `prevent_destroy` is a plan-time control and is not read back); they defend against mistaken deletes, NOT against a holder of the read/write Hetzner token ..." (the last clause describes the control's design scope, unchanged).

### Phase 4 - Legal registers (CLO wording)

1. `article-30-register.md` PA-13 (g) item (13): in the heading, replace the parenthetical "adopting: in force only once PR #9925 is merged, its apply has landed and the post-apply read-back passes" with "accepted 2026-10-15, #10018; see marker" (so it reads "(#9879, ADR-282; accepted 2026-10-15, #10018; see marker)"); append at the end of the item (13) text, inside the same table cell, this marker (CLO-approved, 79 words):

   > **[Superseded 2026-10-15 (#10018): the qualifier "adopting: in force only once PR #9925 is merged, its apply has landed and the post-apply read-back passes" is discharged. PR #9925 merged 2026-10-11; apply run 38139392390 landed the volume update (job later failed on an unrelated step); Hetzner read-back on 2026-10-15 returned `protected`. Point-in-time, flag only; `prevent_destroy` is plan-time, not read back live. Accepted residuals and the absent Art. 32(1)(c) restore capability are unchanged.]**

   Do NOT bump `last_reviewed`. Before writing any "the cell now reads" claim anywhere, grep the cell.
2. `compliance-posture.md` row ~205: append inside the row, after "The earlier text is left as written." and before the closing `**]**`, separated from it by a space (`written. **[Superseded ... unchanged.]** **]**`, never `]****]`), this marker (CLO-approved, 63 words):

   > **[Superseded 2026-10-15 (#10018): "adopting until the post-apply read-back passes" is discharged. PR #9925 merged 2026-10-11; apply run 38139392390 landed the volume update (job later failed on an unrelated step); read-back on 2026-10-15 returned `protected`. Point-in-time and flag only; `prevent_destroy` is plan-time, not read back live. Residuals, the missing Art. 32(1)(c) restore capability and the no-crypto-erasure statement stand unchanged.]**

   Keep the bold and bracket pairing balanced (an even count of `**` in the cell, no stray `]`). Do not bump `last_updated` or add a header comment (CLO L3 permits it, nothing requires it; plan-review cut it as the only inferred item).
3. The markers are the CLO's verbatim text and need no further CLO round-trip unless `soleur:ship` Phase 5.5 requires an attestation for amending legal docs; if it does, send the final diff text of both legal files to `soleur:legal:clo` (read-only, "do NOT use AskUserQuestion") for the DISCHARGED or BLOCKED verdict (CLO L3) and apply any wording correction.

### Phase 5 - Verification (targeted suites only; CI is the authority)

Run each gate's OWN invocation, not a hand-enumerated reconstruction of its input set:

1. `bash apps/web-platform/infra/inngest-luks-sole-copy.test.sh` (Guard 1: H1b heading exists, H2 byte-identical read-back one-liner between runbook and postmerge skill; the runbook is in `infra-validation.yml` `pull_request.paths`, so CI runs this advisory job).
2. `python3 scripts/lint-encryption-posture.py` and `bash scripts/lint-encryption-posture.test.sh`; `python3 -c 'import json;json.load(open("scripts/encryption-posture-ledger.json"))'`.
3. `bash plugins/soleur/test/c4-count-parity.test.sh` and `bash plugins/soleur/test/c4-model-freshness.test.sh` (the C4 syntax and render tests run in CI).
4. `bash scripts/lint-legal-registers.sh` (blocking in CI) and `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` (the same invocation CI uses).
5. `bash scripts/check-adr-ordinals.sh` and `bun test plugins/soleur/test/adr-frontmatter-ordinal-guard.test.ts`.
6. The repo markdown lint the lefthook config runs on the changed files.

### Phase 6 - Ship, merge, post-merge (the agent owns all of it)

1. Commit with the trailer `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`; no commit message, PR title or PR body contains a closing keyword (`close`, `closes`, `closed`, `fix`, `fixes`, `fixed`, `resolve`, `resolves`, `resolved`) before `#10018`; use `Ref #10018`.
2. PR title (example): `docs(adr): accept ADR-282 and flip its sister records (Ref #10018)`. PR body states: the evidence (word, date, volume id, derivation, run-conclusion wording above), that ADR-199 was added beyond the issue list, the explicit out-of-scope list, and ends with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`. `soleur:ship` full-replaces the body: make sure its generated text keeps `Ref #10018` and carries no closing keyword.
3. After EVERY body or title edit: `gh pr view <N> --json closingIssuesReferences --jq '.closingIssuesReferences | length'` must print `0`.
4. Merge queue is on for main: BEHIND is expected; never sync a queued or armed PR by hand. If a sync is needed before arming, merge main with a merge commit (never rebase, no `git stash`). Once the required checks are green, queue auto-merge (`gh pr merge <N> --auto --squash`, then confirm `autoMergeRequest` is set and the PR enters the queue). The advisory Guard 1 job is not required but is expected to pass.
5. Post-merge (docs-only, no apply fires because no `apps/web-platform/infra/**` path changes): confirm the merge commit on main contains the edits; `postmerge` Phase 5.7 records `Sole-copy read-back: SKIPPED (no triggering paths)` and makes no Hetzner call; confirm the merge diff on main matches the PR (AC-1, AC-4, AC-5 hold on `origin/main`). Then close #10018 with a comment citing the merge commit (closure by the agent after verification, not by a body keyword).
6. Final report includes the #10081 status: it is an OPEN draft PR labelled `parked` with no auto-merge armed (head `feat-one-shot-9786-strip-plain-id-resolver`, mergeStateStatus UNKNOWN at plan time). This PR does not touch, update, mark ready, queue or merge it, and runs no host replace; the "first sanctioned host replace" stays unperformed (ADR-282's live proof of detach under delete protection is still pending). Re-read its state at report time.

## Acceptance Criteria

### Pre-merge (PR)

- [x] AC-1 ADR status: `sed -n '1,12p' knowledge-base/engineering/architecture/decisions/ADR-282-sole-copy-luks-volume-protection-set.md | grep -c '^status: accepted$'` prints `1` and `grep -c '^status: adopting'` on the whole file prints `0`.
- [x] AC-2 ADR-282 addendum: `grep -n '^## Addendum — 2026-10-15 (#10018' <ADR-282>` finds one line and `grep '^## ' <ADR-282> | tail -1` is that heading; the section contains, each at least once, `protected`, `106903269`, `38139392390`, `38653889114`, `67cb281e4f`, `delete_protection = true`, `2026-10-15`. Review checks (not greppable): the read-back line states a date and no time-of-day (the run timestamps 12:32:53Z and 12:48:18Z are quoted as measured); the sentence about run 38139392390 never calls it green or successful (run 38653889114 is the one reported as succeeded); no token value. The leading "Accepted 2026-10-15 (#10018)" blockquote sits between `## Status` and the "Adopting - 2026-10-10" paragraph, which is still present.
- [x] AC-3 Sister markers: each of ADR-119, ADR-142, ADR-263, ADR-199 gains exactly one `Superseded 2026-10-15 (#10018), as to "adopting"` blockquote, directly after the stale sentence it supersedes (verify with `grep -n -B2` that the preceding paragraph is the stale one; ADR-142's sits under "Status of this addendum: adopting"); `git diff origin/main -- <those four>` shows additions only (no removed lines) and no frontmatter hunk.
- [x] AC-4 Runbook: `grep -c -E 'do not assume it exists before then|Until then treat the live volume as unprotected|effect on the merge of PR #9925|^\*\*Status: adopting' knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md` prints `0` (the pattern `effect on the merge of PR #9925` is deliberately the second line of a wrapped sentence: "takes" ends line 330, so a pattern starting at "takes" matches nothing before OR after and would be a vacuous check; confirm the pattern returns 1 on `origin/main` first) and `grep -c '^\*\*Status: accepted 2026-10-15 (#10018' ...` prints `1`; the Guard 1 suite (Phase 5 step 1) is green, which pins the heading and the byte-identical read-back one-liner (the AC is the suite itself, not a restated grep).
- [x] AC-5 C4 and ledger: `grep -c 'conditional: in force only once PR #9925' knowledge-base/engineering/architecture/diagrams/model.c4` prints `0`, same for `model.likec4.json` (which carries the string at 3 description strings before the edit - 5 matching lines - and the diff must show exactly those 3 strings changed; a hand edit is detectable); `grep -c 'take effect on the merge of PR #9925' scripts/encryption-posture-ledger.json` prints `0`; and `jq -e '.stores[] | select(.store=="hcloud_volume.inngest_redis_luks") | .at_rest | (.mechanism=="luks" and (.live_verification|startswith("unavailable:")) and (.does_not_defend|contains("were declared in Terraform by #9879")))' scripts/encryption-posture-ledger.json` exits 0 (`-e` exits 1 on false, so it can fail); the ledger lint and its test pass; `c4-model-freshness` (`plugins/soleur/test/c4-model-freshness.test.sh`) passes, which proves the JSON came from the renderer.
- [x] AC-6 Subject-sweep residual (the non-vacuous form): rerun the repo-wide subject grep over non-archived paths; every remaining hit that contains `adopting` or "in force only once" for THIS subject is either inside a history block that is immediately followed by a `Superseded 2026-10-15 (#10018)` marker (ADR-282 Status prose, ADR-119/142/263/199 addenda, the Article 30 and compliance-posture quoted qualifiers) or is another subject (named in the sweep table). The count of such hits per file is listed in the PR body; a hit with no marker fails the AC. Non-vacuity: run the AC-4 and AC-5 greps once against `origin/main` first; they must print non-zero there (no file is mutated).
- [x] AC-7 Legal: both markers match the CLO-approved text above; the Article 30 heading parenthetical reads `(#9879, ADR-282; accepted 2026-10-15, #10018; see marker)`; the item (13) cell and the compliance-posture row each have an even number of `**`, `grep -c '\]\*\*\*\*'` over both files prints `0` (no four adjacent asterisks), and the compliance-posture row has exactly one extra balanced `[...]` pair (the new marker nested before the existing closing `**]**`, separated from it by a space); `last_reviewed` in the Article 30 front matter is still `2026-09-14`; `bash scripts/lint-legal-registers.sh` passes; if `soleur:ship` Phase 5.5 required an attestation, the CLO verdict on the final diff text is DISCHARGED (or its corrections are applied).
- [ ] AC-8 Closing references: `gh pr view <N> --json closingIssuesReferences --jq '.closingIssuesReferences | length'` prints `0` after PR creation and after every body edit; `git log origin/main..HEAD --format=%B | grep -c -i -E '(close[sd]?|fix(e[sd])?|resolve[sd]?) +#10018'` prints `0`; the PR title and body contain `Ref #10018`.
- [x] AC-9 Boundaries: `git diff origin/main --name-only` is a subset of Files to Edit plus the pipeline-written files listed there; it contains no path under `knowledge-base/legal/audits/`, `apps/`, `.github/`, `plugins/soleur/skills/`, and no `*.tf`; no mention of `106443278` is added to any record (`! git diff origin/main -- . ':!knowledge-base/project' | grep -q 106443278` exits 0; the plan and spec artifacts under `knowledge-base/project/` name it only in the out-of-scope list).
- [x] AC-10 Each claim the addendum adds traces to a cited source: the HCL (`git show origin/main:apps/web-platform/infra/inngest-redis-luks.tf`), the run log (one call: `gh run view 38139392390 --log | grep -c 'Apply complete! Resources: 0 added, 1 changed, 0 destroyed'` is at least 1), and the brief's read-back word.
- [ ] AC-11 Targeted suites from Phase 5 pass locally; required CI (`test`, `encryption-posture`, and the rest of the ruleset contexts) is green.
- [x] AC-12 `knowledge-base/project/specs/feat-one-shot-10018-adr-282-adopting-to-accepted/decision-challenges.md` is present with the `| Item | Class | Ruling |` rows T1-T8, L1-L3, X1. No operator-class rows exist, so no `action-required` issue is filed.

### Post-merge (agent-run, read-only GitHub reads)

- [ ] AC-13 Main carries the edits (AC-1, AC-4, AC-5 greps pass against `origin/main`).
- [ ] AC-14 No `apply-web-platform-infra.yml` run was triggered by the merge commit; postmerge Phase 5.7 is recorded as SKIPPED (no triggering paths); no Hetzner, Doppler or production call was made.
- [ ] AC-15 #10018 is closed by the agent with a comment citing the merge commit; `gh pr view` (merged) shows `closingIssuesReferences` empty.

Report item (not an acceptance check): #10081 is reported as still OPEN, draft, labelled `parked`, no auto-merge armed, and untouched by this work.

## Test Scenarios

- Guard 1 H1b (heading present) and H2 (read-back parity): green after the runbook edit; red if the heading text or the one-liner is touched (that is why Phase 2 forbids it).
- Ledger lint: the edited `does_not_defend` string keeps the row valid; a row whose `mechanism` or `live_verification` changed would be a separate red.
- C4 gates: a description-only edit leaves `c4-count-parity` green; a hand-edited JSON would fail the freshness test (`c4-model-freshness`).
- Legal-register lint: markers carry no unresolved-marker tokens (`TBD`, `TODO`) and keep table cells on one line.

## Risks

- **Over-claim (primary).** The flip invites present-tense "protected" everywhere. The tense rule (X1) and CLO limits bound every cell; AC-10 requires a source for each claim.
- **Hiding the failed job.** Run 38139392390's conclusion is `failure`. The text states it as the run that landed the update and failed later on an unrelated step; the brief's "all succeeded" is not repeated.
- **Byte-identity coupling.** Editing the runbook near the read-back risks Guard 1 H2. Phase 2 forbids touching the one-liner; AC-4 runs the suite.
- **Bold/bracket pairing in a long table cell** (compliance-posture, Article 30). AC-7 checks pairing and the legal lint.
- **Generated JSON.** Hand edits are forbidden; if the renderer cannot run locally the pre-commit hook or CI regenerates it, and the freshness test is the gate.
- **Main moves.** Phase 0 re-sweeps; a sibling PR could add a new ADR-282 mention. The sweep is re-run before arming auto-merge.
- **Sensitive reach.** ADR-282's threshold is `single-user incident`; `soleur:ship` Phase 5.5 may ask for attestation on legal docs. The CLO verdict (AC-7) is that review of form; no new audit file is created unless that gate demands it.

## Non-Goals / Out of Scope

web-2 workspaces volume, git_data volume, rehearsal volume, ADR-198 baked credentials, #6897, #8527, #10081 (parked), web-1
workspaces LUKS volume 106443278 (never touched, never named in new text), the destruction records and counsel reviews under
`knowledge-base/legal/audits/`, `plugins/soleur/skills/postmerge/SKILL.md`, any `.tf`, workflow or script. Deferral tracking:
nothing new is deferred; the pre-existing deferred residuals stay tracked by #9927 (open).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Filled above.
- The diff-scope AC lists pipeline-written files (INDEX.md, session-state.md, tasks.md, decision-challenges.md) on purpose.
- AC-6's grep must be able to fail: the control step re-inserts a stale string and expects non-zero; do not replace it with a bare `== 0` count over files that legitimately keep history.
- Legal edits are quoted verbatim from the CLO; do not paraphrase them when applying.
- Do not print the Hetzner or Doppler responses anywhere; the only recorded read is the single word.
