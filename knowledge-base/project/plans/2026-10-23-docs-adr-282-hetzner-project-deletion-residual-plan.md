---
title: "docs: settle the Hetzner project-deletion residual in ADR-282 from documentation only (#9927 item 7)"
type: docs
date: 2026-10-23
slug: adr-282-hetzner-project-deletion-residual
branch: feat-one-shot-9927-item7-hetzner-project-deletion
issue: 9927
closes: []
lane: cross-domain
requires_cpo_signoff: false
---

# docs: settle the Hetzner project-deletion residual in ADR-282 from documentation only (#9927 item 7)

Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed). No spec.md exists for this branch.

Tracker #9927 stays open on purpose; this PR uses `Ref #9927` and `Ref #10112` only. ADR-282 records, as a residual, that Hetzner project deletion or account loss is not covered and that whether delete protection blocks a project deletion is unverified. Item 7 asks to settle that from Hetzner documentation. The operator dropped the optional scratch-volume detach proof, because it is a Hetzner write.

Result of the documentation read (2026-10-23): **the pages read are silent.** Pages not read: Hetzner terms and conditions, the projects documentation, the cloud changelog, the Terraform provider and `hcloud` documentation. It says volume delete protection blocks deleting the volume, and says nothing about whether it blocks deleting the containing project or surviving account loss. The plan therefore records "not established" with a conservative planning posture, and does not claim "blocks" or "survives".

## Enhancement Summary

**Deepened on:** 2026-10-23
**Passes run:** plan-review (DHH, Kieran, code-simplicity reviewers), a sharp-edges catalogue pass, a CTO ruling, and the deepen-plan gates 4.6 to 4.12. Not run: the open-ended skill, learnings and 40-agent fan-out of deepen-plan sections 2 to 5, because the change is a one-file wording edit to an accepted ADR and the passes above covered its risks; this is a disclosed narrowing.

**Key improvements:** (1) acceptance checks rewritten to run on the flattened residual section and the new addendum only, so an old addendum or the wrapped line cannot satisfy or defeat them; (2) the evidence class renamed "documented, not measured" to match the ADR's own legend, and the verdict worded "not found in the pages read"; (3) the loss-mode rows in the ADR and the cutover runbook, and the legal registers, checked and found consistent with the new posture, so no further edit.

**Gate results:** 4.6 present, threshold `none`, files are documentation only (no sensitive path); 4.7 skipped (pure docs); 4.8 no PAT-shaped match; 4.9, 4.10, 4.11 not triggered (no UI, no store or connection, no guard); 4.12 one live `## Scope Check`, all three subsections present, no `unmapped` row, a `Recommendation:` line present. Cited issues #9927, #10112, #10664 and PR #10874 are open (checked 2026-10-23 with `gh`); the one rule id cited, `hr-technical-fork-is-not-an-operator-question`, is active.

## Research Insights

**Premise validation (2026-10-23).** #9927 and #10112 are open. ADR-282 `### Residuals recorded, not mitigated` carries the residual verbatim ("Hetzner project deletion or account loss is not covered; whether delete protection blocks a project deletion is unverified"). A repo grep (`git grep -Ei 'project loss|account loss|project deletion|despite protection'` over `knowledge-base` outside archives and learnings) finds that ADR-282 residual as the only statement of the open question. Two other rows say the same outcome in other words and are consistent with the new posture, so neither needs an edit: the ADR's loss-mode table row "Hetzner volume deleted despite protection, or project loss" (recovery: none) and the same row in `knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md` ("No recovery"). The legal registers (`article-30-register.md` PA-13 and PA-1 TOM text, the counsel audits) describe delete protection as a control against mistaken deletion and none claims it covers project or account loss, so there is no legal edit. Open PR #10874 also edits the inngest-server runbook, which this plan leaves untouched to avoid a conflict. `knowledge-base/engineering/operations/runbooks/tenant-provisioning.md` and `plugins/soleur/skills/provision-hetzner/scripts/provision-hetzner.sh` say the Hetzner CLI does not support project deletion; that is tenant teardown tooling and unrelated. The archived sole-copy plan (row 12 and its deferral) is a point-in-time record and is not edited. No ADR rejects the mechanism (the mechanism is a wording change).

**Property List.**

1. A reader of ADR-282 can tell what is and is not known about project deletion or account loss versus delete protection, and from where.
2. The posture decisions rest on a stated planning posture, not on an unproven protection claim.
3. The addendum states what was measured and what was not, with dates and URLs.
4. The first sanctioned inngest-host-replace is not misread as settling this residual.

**Cut List.** (a) Scratch-volume detach-under-delete-protection proof: a Hetzner write; the operator dropped it; the first sanctioned inngest-host-replace is the live detach proof (and proves nothing about project deletion). (b) Runbook edit: no runbook states the residual (grep above), so none is made. (c) Off-project copy or any new mechanism: out of scope for this item; if the posture later needs operational backing it is a separate item.

**Documented, not measured (2026-10-23; public documentation files read; no Hetzner API call, no account access). The ADR's own evidence vocabulary reserves "measured" for live reads, so this class is "documented".**

- `https://docs.hetzner.cloud/cloud.spec.json` (HTTP 200, 3.5 MB), `DELETE /volumes/{id}`, "Delete a Volume": "The Volume must not be attached to a Server and it must not have delete protection enabled."
- Same file, `POST /volumes/{id}/actions/change_protection`: the `delete` flag is "If true, prevents the Volume from being deleted." The Detach Volume action's description does not mention protection. A text search of the whole spec finds zero places that pair "project" with "delet".
- `https://docs.hetzner.com/cloud/servers/faq/` (HTTP 200): "Before you can delete a protected resource, you have to deactivate the deletion protection." The same page names servers, snapshots and floating IPs as protectable (volumes are not named on that page) and calls protection "an additional safeguard for accidental deletion".

**Documentation NOT found (2026-10-23).** No page saying whether protection blocks deleting the containing project, or what happens to protected resources when an account is closed or terminated. `https://docs.hetzner.com/accounts/` returned 404; the cloud general FAQ (`https://docs.hetzner.com/cloud/general/faq/`) holds no such statement; the data-protection page (`https://docs.hetzner.com/general/company-and-policy/data-protection-at-hetzner/`) was fetched and its account-deactivation and account-deletion entries were read in full: they name inactivity and non-payment as deactivation reasons and "no more active products and all outstanding invoices paid" as the precondition to delete an account, and say nothing about projects, cloud resources or protection. The verdict is therefore worded "not found in the pages read on 2026-10-23", not "Hetzner has no such behaviour". An earlier planning pass in this session reported two sentences from a cancellation page; that page could not be located again on 2026-10-23, so those sentences are **not cited** here.

**Not measured:** no live Hetzner call of any kind; no project or account behaviour; no support answer from Hetzner.

**Technical ruling.** `Ruled by CTO agent, 2026-10-23: Option B — state the planning posture "plan as if project deletion or account loss destroys the volume regardless of delete protection", and label the underlying fact "not established; Hetzner docs read 2026-10-23 are silent"; add a dated addendum and an in-place parenthetical on the residual - docs-silent evidence does not separate the options, so the stricter one wins: assuming protection survives costs sole-copy data loss, assuming it does not costs nothing. Delete protection must never be cited as cover against project or account loss.` Also ruled the same day: name the settlement route as non-binding (a written Hetzner support question is an owner-side read-only act; a live test is out of scope because project deletion is irreversible; do not call it the only route and do not make it a gate), and say explicitly that the first sanctioned inngest-host-replace proves detach under protection only. Third item, same date: no runbook edit is needed, confirmed by re-running the grep.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Item 7: Hetzner project-deletion coverage. Docs read only, no writes." [brief] | Files to Edit: ADR-282 residual and addendum | mapped |
| 2 | "Drop the scratch-volume detach proof (a Hetzner write); the first sanctioned replace is the live proof." [brief] | Addendum sentence on the dropped proof; Cut List (a) | mapped |
| 3 | "Each PR body states what was measured and what was not, with dates." [brief] | Addendum "Measured versus not measured"; PR body at ship | mapped |
| 4 | "Never print diffs, values, version contents, user identifiers or personal data; names and metadata only." [brief] | Acceptance Criteria AC5 | mapped |
| 5 | "After each item: update the #9927 tracker with a comment (names and dates only), then emit the next resume prompt." [brief] | Post-merge step (Phase 3) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Edit ADR-282 residual in place | "Item 7: Hetzner project-deletion coverage." | asked |
| Append ADR-282 addendum | "Each PR body states what was measured and what was not, with dates." (asks 1, 3) | asked |
| `decision-challenges.md` row for the CTO ruling | — | inferred — justification: the repo's technical-ruling gate needs the ruling persisted before `soleur:work` |
| `tasks.md` | — | inferred — justification: the pipeline derives it from the plan |

### Split Assessment

- Subsystems touched: 1 — `knowledge-base/engineering/architecture/decisions/`
- Planned files: 1 edited + 3 planning artifacts | Estimated changed lines: ~40
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly: it is an architecture-record wording change, with no code, config or infrastructure effect.
- **If this leaks, the user's data is exposed via:** no vector; the addendum carries public documentation URLs, dates and names only, and no values, identifiers or personal data.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** `none`, not `aggregate pattern`: the change adds no capability and removes none; its only risk is a misleading sentence, and the CTO ruling picks the stricter wording to remove that risk.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO ruling above (2026-10-23): conservative posture wording, non-binding settlement route, no runbook edit. No product, marketing, legal, finance, sales, support or operations implication: no UI, no data-processing change, no sub-processor change, no spend. The wording change does not alter any legal statement; ADR-282's Art. 32(1)(c) supersede markers are untouched.

## Files to Edit

- `knowledge-base/engineering/architecture/decisions/ADR-282-sole-copy-luks-volume-protection-set.md`: (1) in the residual "Hetzner project deletion or account loss", replace "is unverified" with the CTO wording and a pointer to the new addendum (an in-place parenthetical, as the item 8c addendum did for another residual); (2) append `## Addendum — 2026-10-23 (#9927 item 7, Hetzner project-deletion coverage, documentation read only)` after the last addendum.

## Files to Create

- `knowledge-base/project/plans/2026-10-23-docs-adr-282-hetzner-project-deletion-residual-plan.md` (this file)
- `knowledge-base/project/specs/feat-one-shot-9927-item7-hetzner-project-deletion/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-9927-item7-hetzner-project-deletion/decision-challenges.md`

No edit to the inngest-server runbook (open PR #10874 edits it), `rehearsal.tf`, any workflow, any `.tf` file or the archived sole-copy plan.

## Open Code-Review Overlap

None. (Checked against open `code-review` issues for the one edited path before work starts; a non-empty result is recorded in session-state and dispositioned there.)

## Architecture Decision (ADR/C4)

No new architectural decision: the plan amends the wording of one residual in an accepted ADR through the addendum convention the ADR already uses. C4: no impact. Checked: external actors (no new human actor), external systems (Hetzner is already modelled; no new edge), data stores (no change to the volume or Doppler or state edges), actor-to-surface access (unchanged). No `.c4` file is edited.

## Acceptance Criteria

The ADR wraps prose at about 120 columns, and earlier addenda already hold some of the phrases below, so checks run on two flattened pieces of text, never on a line-based grep and never on the whole file where an old addendum could satisfy them. Define, after the edit: `FLAT() { tr '\n' ' ' | tr -s ' '; }`; `RESID=$(sed -n '/^### Residuals recorded, not mitigated/,/^### Enforcement posture/p' <ADR> | FLAT)` (the residuals section); `ADD=$(sed -n '/^## Addendum — 2026-10-23 (#9927 item 7/,$p' <ADR> | FLAT)` (the new addendum to end of file). Use `printf '%s' "$RESID" | grep -c ...`, `printf '%s' "$ADD" | grep -c ...`.

- [x] AC1. The residual carries the posture and the status and the old ending is gone, checked on `RESID` only (the addendum may quote the old sentence): `grep -c 'destroys the volume regardless of delete protection'` is at least 1, `grep -c 'not established'` is at least 1, `grep -c 'whether delete protection blocks a project deletion is unverified'` is 0. Baseline on `origin/main`: the first two are 0 and the third is 1 on the flattened text.
- [x] AC2. The addendum is the last one and opens like its siblings: `grep -n '^## Addendum — ' <ADR> | tail -1` shows `2026-10-23 (#9927 item 7`, and `ADD` starts, after its heading, with "Appended; the only change above is the residual" and contains "Status stays `accepted`".
- [x] AC3. `ADD` names what was documented and what was not found, with URLs and the date: `grep -c 'docs.hetzner.cloud/cloud.spec.json'`, `grep -c 'docs.hetzner.com/cloud/servers/faq'`, `grep -c 'documented, not measured'` and `grep -c 'not found in the pages read'` are each at least 1 on `ADD` (the third and the opener phrase already exist in older addenda, which is why the check is scoped to `ADD`).
- [x] AC4. `ADD` states the scratch-volume detach proof is dropped, that the first sanctioned inngest-host-replace proves detach under protection only and does not settle project deletion, the one-sentence non-binding support-question route, and the ruling line: `grep -c` of each of `scratch-volume`, `proves detach under protection only`, `support question` and `Ruled by CTO agent, 2026-10-23` is at least 1 on `ADD`.
- [x] AC5. After the commit exists: `git diff origin/main...HEAD --name-only` is a subset of {the ADR, this plan, `tasks.md`, `decision-challenges.md`, `session-state.md` under the spec directory} and contains the ADR; the added ADR lines hold no value, token or identifier: `git diff origin/main...HEAD -U0 -- <ADR> | grep '^+' | grep -Ec '[0-9]{8,}|[A-Za-z0-9+/]{40,}|@'` prints at most the count produced by the id `106903269` already named in the text (the check is read by a person against that one expected hit, not assumed 0), and `git show origin/main:<ADR> | grep -c 'Hetzner id 106903269'` equals `grep -c 'Hetzner id 106903269' <ADR>`.
- [x] AC6. The ADR's consumers stay green, run one at a time and derived from the reference list: `git grep -l 'ADR-282' -- '*.test.sh' '*.test.ts'` names the suites to run (at least `apps/web-platform/infra/inngest-redis-luks-import-rehearsal.test.sh` and `plugins/soleur/test/sole-copy-drift-check.test.sh`), plus `bash scripts/check-adr-ordinals.sh` and `npx markdownlint-cli2 <ADR>`; each exits 0.
- [ ] AC7. The PR body says what was documented and what was not found, with dates, uses `Ref #9927` and `Ref #10112` and no closing keyword, and ends with the Claude Code attribution line (checked with `gh pr view <N> --json body` at ship).

**Plan-review consolidation (2026-10-23).** Mechanical, applied: AC commands made discriminating across the line wrap (Kieran P1, P2); evidence class renamed "documented, not measured" to match the ADR's legend (Kieran P2); AC5 moved after the commit (Kieran P2); addendum opener "Appended; the only change above is the residual" added (Kieran P3); eight ACs collapsed to seven; verdict worded "not found in the pages read" and the data-protection entries read in full (DHH P2). Kept against reviewer proposals, because they are the operator's direction and not a taste call: the `Ruled by CTO agent` line in the addendum and `decision-challenges.md` (the brief says "Rulings start `Ruled by CTO agent, <date>: ...`"), the one-sentence support-question route (CTO ruled it in), and the PR-body measured / not-measured statement (the brief requires it). Applied as simplification: the addendum carries a short documented / not-found / not-measured list in place of a table.

## Test Scenarios

Docs-only change; the suites named in AC6 are the regression guard for the ADR's consumers. No new test file: no guard is introduced.

## Implementation Phases

**Phase 1 — edit.** Read the ADR again (compaction erases reads), edit the residual in place, append the addendum: opener "Appended; the only change above is the residual ... Status stays `accepted`.", a short documented / not found / not measured list, the dropped-proof and host-replace sentences, the one-sentence support-question route and the CTO ruling line. Keep the posture sentence on one line or accept that AC1 runs on the flattened text.

**Phase 2 — verify.** Run the AC commands; run the suites and the lint in AC6 sequentially (never concurrently with the pre-push gate). The technical-ruling gate (`bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch`) already passed on 2026-10-23 with three rows examined.

**Phase 3 — ship and close the loop.** Review, ship through `soleur:ship`. After merge: post a comment on #9927 naming item 7 done with dates and the PR number (names and dates only), then print the resume prompt for item 2 (#10664 site C).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6; this plan fills it.
- Do not quote the cancellation-page sentences from the earlier pass: they were not re-verified on 2026-10-23.
- The addendum must not call the residual "settled": the result is "not found in the pages read, not established".
- Read the whole ADR section before editing: a stale read-before-edit after compaction is how addenda get duplicated.
