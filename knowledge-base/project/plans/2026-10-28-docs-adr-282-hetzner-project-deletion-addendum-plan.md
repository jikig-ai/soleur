---
title: "docs(adr): ADR-282 addendum 2026-10-28, Hetzner project-deletion coverage, what was measured and not"
date: 2026-10-28
slug: adr-282-hetzner-project-deletion-addendum
branch: feat-one-shot-9927-adr-282-hetzner-project-deletion-note
issue: 9927
type: docs
lane: single-domain
---

# docs(adr): ADR-282 addendum 2026-10-28, Hetzner project-deletion coverage

Detail level: MINIMAL. Docs only; one append to one file. PR #11414 (draft). Work item 5(a) of the Inngest LUKS epic #9927 (epic item 7, follow-up 1, from the CTO analysis comment of 2026-10-26). `Ref #9927` and `Ref #10112` only; no closing keyword in the PR title or body (`wg-use-closes-n-in-pr-body-not-title-to` does not apply: nothing here closes an issue). #10889 (merged, the 2026-10-23 addendum) is cited as a plain reference.

## Overview

Append one dated addendum, `## Addendum - 2026-10-28 (#9927)`, at the end of `knowledge-base/engineering/architecture/decisions/ADR-282-sole-copy-luks-volume-protection-set.md` (currently ends with the `Addendum - 2026-10-26 (#9927)` block, last line the "Superseded (route only)" paragraph). It records, with evidence class and date, exactly what a re-read of two public Hetzner sources showed on 2026-10-28 and what stays unmeasured, and names three owner-side follow-ups as not started. Append-only: no edit to the 2026-10-23 addendum, any dated cell, the Status block, or the residuals. No new ordinal; status stays `accepted`.

## Research Insights

**Premise Validation (Phase 0.6).** Checked: #9927 OPEN, #10112 OPEN, #10889 MERGED (PR "docs(adr): ADR-282 Hetzner project-deletion residual is not established, record planning posture"). The ADR ends with the 2026-10-26 addendum as the brief says; the 2026-10-23 addendum (L366-382) holds the three-row question table, the "planning posture stands" paragraph and a CTO ruling of 2026-10-23. Collision pre-check: PRs #11404, #11374, #11284, #11378 also name #9927; none touches the ADR-282 file (`gh pr diff --name-only`, 0 hits each). Foreign `test-all.sh` processes belong to other worktrees; no overlap with this file.

**Pre-research measurements (read-only, 2026-10-28, plan time; the work phase MUST redo them and cite its own run).**

| Source | What was read | Result |
|---|---|---|
| `https://docs.hetzner.com/general/billing-and-account-management/cancellation/cancellations-hetzner-console/` (section "Deleting a project") | curl 200, tags stripped | Section text, in order: "Make sure that you have deleted all the resources in the project." then the steps, then "Note: If you delete a project, you will permanently delete all associated resources on that project." The quoted sentence is present verbatim. The page says nothing about delete-protected resources blocking a project delete. |
| `https://docs.hetzner.cloud/cloud.spec.json` | curl 200, 3544237 bytes, `jq` | 152 paths; 190 operations; 19 distinct first path segments (this is the "19 groups" definition that reproduces the CTO's figure; the spec also lists 31 `tags` and 11 `x-tagGroups`, so the addendum must name the definition it used); 0 paths matching `project` (case-insensitive) and 0 beginning `/project`; the info description says "A token is bound to a Project, to interact with the API of another Project you have to create a new token inside the Project." |

**Reconciliation, spec/brief vs reality.**

| Brief or earlier record | Reality | Plan response |
|---|---|---|
| The CTO comment names "Hetzner's cancellation page" with no URL. The 2026-10-23 plan could not relocate the cancellation page and deliberately did not cite it. | The page exists at the URL above (`docs.hetzner.com/general/cancellation/` 302-redirects to a 404 path; `/general/others/` links the live one). | Cite the full URL and the fetch date in the addendum, state in one clause that the 2026-10-23 pass did not find it, and do not edit the 2026-10-23 text. |
| Brief: quoted sentence "strengthens" the planning posture. | The same section opens with an instruction to delete all resources first, which could be read either way about protected resources. | Quote both sentences as read; claim limit: neither says whether protected resources block a project delete; the posture rests on the stricter option as ruled 2026-10-23. |
| Brief: "19 groups". | 19 equals distinct first path segments, not `x-tagGroups` (11) or `tags` (31). | Say "19 distinct top-level path segments". |

**Property List (Phase 0.6b).** (P1) A reader of the ADR can see what Hetzner's public docs and API spec say about project deletion, dated, with the exact words quoted. (P2) The ADR states the volume has no cover against project or account loss and that this stays an accepted residual. (P3) Every unmeasured item is listed so no later reader infers more than was read. (P4) The three owner-side follow-ups are named as owner-side and not started, none decided. **Cut List:** a new ADR ordinal (P1-P4 are served by an addendum; the 2026-10-26 addendum set that precedent); a change to the residual cells (already reworded 2026-10-23, would be a dated-cell edit); any script, test, workflow or runbook edit (no property needs one); a scratch-volume or live deletion test (Hetzner write, irreversible, out of scope).

**Learnings applied.** The ADR's own convention: Evidence classes "documented, not measured" / "not measured" (2026-10-22 and 2026-10-23 addenda). Write "not found in the pages read", never "Hetzner has no such behaviour".

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing; an engineering record would overstate or understate what Hetzner documents about project deletion, and a later decision on an off-project copy of the sole-copy volume could rest on it.
**If this leaks, the user's data is exposed via:** no vector; the addendum quotes one public sentence and public API counts, no value, token, account identifier or member name.
**Brand-survival threshold:** none. threshold: none, reason: documentation-only append to an internal ADR, quotes public Hetzner text only and names no credential, person or account.

## Implementation (single phase, `soleur:work`)

1. Re-fetch read-only, in this order, and keep the output out of the repo:
   - WebFetch the cancellation-page URL above; confirm the sentence word for word and read the whole "Deleting a project" section. If the sentence differs or the page is gone, record what was actually read and do NOT quote the old sentence.
   - `curl` the spec to a scratchpad path and count with `jq`: paths (`.paths|length`), distinct first path segments, paths matching `project` (case-insensitive), and read the info-description sentence about tokens. Record the work-phase numbers, not the plan-time ones; if they differ from 152/19/0, say so.
2. Append the addendum (draft shape below) to the end of the ADR. Keep to about 25 lines. No em dashes in new prose.
3. Local checks (cheapest first; CI is the gate, owner decision 2026-10-27; rc 6 is not a pass):
   - `bash scripts/markdown-lint.sh knowledge-base/engineering/architecture/decisions/ADR-282-sole-copy-luks-volume-protection-set.md` (needs a pin-verified binary; if it refuses to run, state that and leave it to the CI job `pr-quality-guards.yml` markdownlint step; do not substitute an unpinned runner).
   - `bash scripts/check-adr-ordinals.sh`.
   - `bash plugins/soleur/test/sole-copy-drift-check.test.sh` (reads the ADR for the volume-id string `Hetzner id 106903269`, row N1; an append cannot break it, run to confirm).
   - `bash apps/web-platform/infra/inngest-redis-luks-import-rehearsal.test.sh` (the ADR path is in `infra-validation.yml`'s PR path list, so CI will run it; it pins `**UNVERIFIED first.**` in the ADR, untouched).
   - `git diff --stat origin/main...HEAD` shows exactly one ADR file plus plan/spec files; `git diff origin/main -- <ADR> | grep -c '^-[^-]'` is 0 (append-only proof).
4. PR #11414 body (`soleur:ship` renders it): state Measured and Not measured with dates (2026-10-28 for this fetch, 2026-10-26 for the CTO comment), `Ref #9927`, `Ref #10112`, no closing keyword, and that #9927 stays open until the owner closes it.

### Draft shape of the addendum (wording is the implementer's; facts must come from step 1)

```text
## Addendum - 2026-10-28 (#9927)

Appended; nothing above is edited and the status stays `accepted`. No new ordinal. Public Hetzner pages were read on 2026-10-28 (analysis first posted on #9927 on 2026-10-26); no Hetzner API call with a credential, console access, write or live test was made. Follows the 2026-10-23 addendum (#10889).

| Question | Answer | Evidence class | Date |
| What does the Hetzner Console cancellation page say about deleting a project? | "<verbatim sentence>" (URL, section "Deleting a project"); the section opens "Make sure that you have deleted all the resources in the project." Neither sentence says whether delete-protected resources block a project delete. The 2026-10-23 pass did not locate this page. | documented, not measured | 2026-10-28 |
| Can either credential tier delete a project through the documented API? | The spec has <N> paths, <M> distinct top-level path segments, none naming a project; its introduction says a token is bound to a Project. So no, by the documented API. The read/write token can still lift protection and delete the volume (existing residual). | documented, not measured | 2026-10-28 |

Still true: nothing protects volume 106903269 if the whole project or account is lost, and no copy of its data exists outside the project; accepted residual, unchanged. The 2026-10-23 planning posture stands; the quoted sentence is consistent with it and does not settle whether protection blocks a project delete.

Not measured: whether protected resources block a project delete in practice; which role may delete a project; what account closure or suspension does; the member list, roles, owner and admin count and sign-in protection (console only, no API endpoint; same list as the pending A6 record). Claim limits: "documented" means the quoted text exists on the date read, not that Hetzner behaves so; the spec check covers the documented API only.

Owner-side follow-ups, none started and none decided here: (1) a read-only console check of members, roles and sign-in protection (also produces the A6 record); (2) a written question to Hetzner support on whether protected resources block a project delete and what account closure does; (3) a decision, a separate spend, on keeping a copy of the ciphertext and LUKS header outside the project, which overlaps the 2027-01-08 header-backup deferral.
```

## Files to Edit

- `knowledge-base/engineering/architecture/decisions/ADR-282-sole-copy-luks-volume-protection-set.md` (append only, after its last line)

## Files to Create

- `knowledge-base/project/plans/2026-10-28-docs-adr-282-hetzner-project-deletion-addendum-plan.md` (this file)
- `knowledge-base/project/specs/feat-one-shot-9927-adr-282-hetzner-project-deletion-note/tasks.md`

## Open Code-Review Overlap

None. Checked 2026-10-28: no open `code-review` issue body names the ADR-282 file path (200-issue snapshot, `jq contains`); the PR-level collision pre-check also found no open PR editing it.

## Architecture Decision (ADR/C4)

Skipped: the addendum records evidence and an unchanged accepted residual; it makes no decision and changes no actor, system or relationship (Hetzner Cloud is already modeled as the `hetzner` container in `model.c4`). Nothing to decide on ordinals.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected: internal documentation append. Legal exposure is not changed (no new data-processing statement); the header-backup question stays legal-gated in the ADR and is not decided here.

## Acceptance Criteria

- [ ] The ADR gains one new final section `## Addendum - 2026-10-28 (#9927)`; `git diff origin/main -- <ADR>` shows additions only (0 removed lines); the Status block and every dated cell are untouched.
- [ ] The cancellation-page sentence is quoted only after the work-phase WebFetch confirmed it word for word, with the full URL, section name and fetch date 2026-10-28; if it did not match, the addendum records what was read and does not quote the old sentence.
- [ ] The spec counts (paths, distinct top-level segments, project-named paths) and the token statement are the work-phase numbers from a fresh `jq` run on 2026-10-28, with the "groups" definition named.
- [ ] The addendum states: no protection against project or account loss; no off-project copy; accepted residual; the 2026-10-23 posture stands; the sentence does not settle whether protection blocks a project delete.
- [ ] The "Not measured" list has all four items (protected resources vs project delete in practice; which role may delete a project; account closure or suspension; member list, roles, owner/admin count, sign-in protection, console only, shared with A6).
- [ ] The three follow-ups are named owner-side, "not started", none decided; no sentence picks an option.
- [ ] No value, token, account id, member name or email in the addendum, plan or PR body.
- [ ] `check-adr-ordinals.sh` and `sole-copy-drift-check.test.sh` exit 0; markdownlint on the ADR exits 0 or the refusal is stated and CI's markdownlint job is green; the PR body has Measured / Not measured with dates, `Ref #9927`, `Ref #10112`, and no closing keyword (`grep -iE '(close[sd]?|fix(e[sd])?|resolve[sd]?) #' ` on the body returns nothing).
- [ ] Only the ADR and files under `knowledge-base/project/{plans,specs}/` changed.

## Test Scenarios

No executable browser or API steps. This is a documentation change; verification is the shell and `jq` checks in Implementation step 3, each read-only (public pages and a public JSON spec; no credential, no Hetzner or Doppler write, no terraform). Mutation view for the one machine-checkable property (append-only): editing any existing ADR line makes `git diff origin/main -- <ADR> | grep -c '^-[^-]'` non-zero; the check is the proof.

## Sharp Edges

- The 2026-10-23 plan found the cancellation page unreachable; a work-phase 404 or changed wording must change the addendum, not be papered over with the 2026-10-26 sentence.
- Do not turn "documented" into "Hetzner behaves so"; the addendum quotes text, it does not measure behaviour.
- The ADR path is in `infra-validation.yml`'s PR path list: CI will run the infra guard suites on this docs-only PR. A red there is not caused by the append unless an anchor the suites grep for was edited (none is touched).
- Rc 6 is not a pass. Do not work in the dirty root checkout.
