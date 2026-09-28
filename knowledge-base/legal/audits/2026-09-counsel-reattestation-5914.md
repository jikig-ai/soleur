---
title: "Counsel re-attestation — #5914 / PR #9096 (host-key step 6: the app's unpinned git-data host-key arm is deleted; discharges re-evaluation triggers (1) and (2) of the #7226 counsel review, trigger (2) conditioned on the merge of PR #9096)"
type: counsel-review
date: 2026-09-28
issue: 5914
related_issues: [7226, 8629, 8572, 8211, 8209, 8442]
pr: 9096
parent_review: knowledge-base/legal/audits/2026-09-counsel-review-7226.md
plan: knowledge-base/project/plans/2026-09-28-feat-git-data-delete-unpinned-fallback-arm-5914-plan.md
adr: knowledge-base/engineering/architecture/decisions/ADR-237-ssh-host-keys-are-pinned.md
brand_survival_threshold: single-user incident
status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)
signed_off_at: 2026-09-28
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; the operator retains an optional veto)"
conditioned_on: "The merge of PR #9096. The trigger (1) discharge is a past fact (2026-09-25) and does not depend on the merge. The trigger (2) discharge and every statement below about the deleted arm, the ledger flip and the message-path cure fire on that merge. If PR #9096 closes unmerged, trigger (2) stays open and those statements are void."
disposition: "DISCHARGED, conditioned on the merge of PR #9096, subject to TWO in-PR conditions (C1, C2). Reviewed against branch head 2bd35fdaff (code commit f10019e04f, records commit 2bd35fdaff). The review found one error in the parent review: its D8 row and O1 note said an Art. 17 erasure report reaches `art17_erasure_incomplete`. Because of #8629 it never did. This record corrects that, and the register now carries five CLO-drafted markers, not four."
blocking_findings: []
required_before_merge_DISCHARGED:
  - "C1 — knowledge-base/legal/article-30-register.md carries the FIVE CLO-drafted markers verbatim, each after its stated anchor: PA-36 (g)(14) activation; PA-36 (g)(14) residual (b) and alert; PA-1 (g)(14); PA-2 (g)(18); PA-36 (g)(2) (#8629). `git diff --word-diff=porcelain origin/main...HEAD -- knowledge-base/legal/article-30-register.md` shows no deleted token."
  - "C2 — File a GitHub issue for O1 before merge (wg-when-an-audit-identifies-pre-existing) and cite it in the PR body. Do not change any docs/legal/** page in this PR."
optional_precision_notes:
  - "O1 — Pre-existing since PR #8442 (#8094), not introduced by this PR. `deleteAccount` deliberately sends the raw `auth.users.id` to Sentry as `extra.gitDataRepoId` so a failed erasure can be located. `hashExtraUserId` and `scrubRecursive` rename only `userId`/`user_id` keys, so this key is never pseudonymized. Before this PR the tagged capture was dropped (#8629), but the same raw value still reached Sentry in the pino-mirror breadcrumb's data and reached Better Stack in the log line. The published Privacy Policy, Data Protection Disclosure and GDPR Policy, and register PA-8 (c)(i), all say user identifiers are pseudonymised at the emission boundary. That is not true for this key. This PR moves the value from a breadcrumb into `extra`. It adds no recipient and no data category, so this finding does not block the merge. The follow-up must either record the exception with its Art. 17 completion basis in PA-8 and the three published policies (which engages the #7387 gates), or replace the raw id with the peppered hash. The controller holds the pepper and can hash every repository name on the host, so the raw id may not be necessary under Art. 5(1)(c)."
  - "O2 — The outer-catch report in `deleteAccount` (`removeGitDataRepo threw …`) stays on the error path. Until #8629 is fixed, it neither reaches `art17_erasure_incomplete` nor matches a tag sweep. Marker 5 says so. The step-5 record's message-text sweep covers it."
  - "O3 — ADR-237's addendum says the residual 'is closed by PR #9096' and ADR-220's entry says 'is met by PR #9096'. Both are engineering records, not attested here, and only land if the PR merges. Rewording them as 'closes on the merge of PR #9096' would match the register's convention. ADR-220's list of remaining flag-flip preconditions names the pin and #8572 but not #8211's per-id re-erasure path. That is for the CTO."
corrections_to_parent_review:
  - "2026-09-counsel-review-7226.md D8 ('Holds') and O1 ('host_key_mismatch IS routed'): wrong in effect. The rule filters on feature and op, but the error-path report never carried those tags in Sentry (#8629). The parent file is not edited. This record and the 2026-09-28 register markers are the correction, and the cure fires on the merge of PR #9096."
attests:
  - "knowledge-base/legal/article-30-register.md: the five 2026-09-28 markers named in C1, and nothing else in the register"
  - "scripts/encryption-posture-ledger.json: the `web-1 app container -> git-data sshd` row as changed by 2bd35fdaff (cert_verification on, exception removed, tls pointer to PR #9096 and the ADR-237 addendum, does_not_defend with four clauses)"
does_not_attest:
  - "The host-key step 5 Art. 17 discharge record (#5914 issuecomment-5865758722). It is a separate merge precondition (plan gate G1), read by the lead with its re-sweep from 2026-09-28T07:51:53Z. This record neither relies on nor certifies it, and no register marker claims that step 5 discharged anything."
  - "ADR-237's addendum, ADR-220's amendment entry, the runbook, the C4 model and the plan. These are engineering records, relied on for the sequence of events."
  - "The code and tests themselves. Counsel attests the record's statements about these controls, not whether the controls are correct."
art_33_triggered: false
art_34_triggered: false
re_evaluation_triggers: "(1) Any proposal to set GIT_DATA_STORE_ENABLED. Parent trigger (3) is now half met (pin present, arm deleted on merge), but #8211's per-id re-erasure path and #8572's paging still stand, and a flip before both is a hard block. (2) Any `pin_absent:` or `pin_invalid:` erasure outcome, or a `pin_absent_at_startup` event, in prd. The Art. 12(3) clock runs from the first such event, and each one goes to a clo-attestation issue with that deadline in its title (runbook pin-fault row). (3) #8629 is fixed fleet-wide. Re-read the 'stays on the error path' clauses of markers 2 and 5 and O2. (4) O1's follow-up lands. (5) PR #9096 closes unmerged: trigger (2) of the parent review re-opens. (6) Inherited unchanged: parent triggers (4) and (5), and the standing external-counsel triggers (first arms-length data subject, EEA-out transfer, regulated-industry data subject)."
addendum_2026_09_28_8572: "Fires on the merge of the #8572 PR with a green apply-sentry-infra.yml run and a green web-platform-release.yml run after it, or not at all: supersedes the D4 paging note and the D6 trigger set, HALF-discharges re_evaluation_triggers (1) (#8572 paging met, #8211 per-id re-erasure path still a hard precondition for the first GIT_DATA_STORE_ENABLED flip), and moves trigger (2) from pulled to paged. See ## Addendum (2026-09-28, #8572)."
---

# Counsel re-attestation: #5914 / PR #9096 (the app's unpinned host-key arm is deleted)

This file is the evidence for the ship Phase 5.5 Counsel-Review CLO-Attestation Gate on PR #9096.
It discharges re-evaluation triggers (1) and (2) of `2026-09-counsel-review-7226.md`, which is not
edited. The CLO agent is the v1 attestation authority, and the operator holds an optional veto.
Everything here is draft material that requires professional legal review. External counsel
re-review is reserved for the triggers above.

## Triggers discharged

- **Trigger (1): post-merge step 3 completes. DISCHARGED as a past fact.** After replace run
  36118115758 published `GIT_DATA_SSH_HOST_KEY` to Doppler `prd`, the redeployed app logged
  `git_data_pin=present fp=SHA256:4eErmLfOuKM17zzNd+2so+26zojG0tsv9NMVNCuXpCs` at
  2026-09-25T09:39:39Z (#5914 issuecomment-5830287903, read 2026-09-28). The PA-36 (g)(14) status
  changes inside its own cell, through the first 2026-09-28 marker. That happens three days after
  activation, not before it. During those three days the register understated the control, which is
  the safe direction. PA-36 as a processing activity is not activated, and the store holds no
  repository.
- **Trigger (2): #5914 deletes the arm. DISCHARGED on the merge of PR #9096.** Residual (b) closes
  inside its cell through the second marker. The PA-1 (g)(14) and PA-2 (g)(18) sibling sentences get
  their own markers. The ledger row flips to `cert_verification: on` with its #5914 exception
  removed. ADR-237 carries "Addendum — PR #9096 (#5914): the transitional app arm is deleted". The
  flip, the addendum and a register marker that names the flip together satisfy the parent's
  requirement that residual (b) and the ledger exception be "rewritten in place with Superseded
  markers". No schema field is needed (CLO, 2026-09-28).

## Scope and limit check

- **Append-only.** Every marker is appended after existing text in its cell. No sentence is removed,
  and no Status or lawful-basis cell is touched (condition C1 checks this).
- **Conditioning is stated.** Each marker that depends on the merge says it "fires on the merge of
  PR #9096" and says what becomes void if the PR closes unmerged. The past-fact parts (activation
  and the #8629 tag loss) are stated without that condition, because they are true either way.
- **No published surface engaged.** No `docs/legal/**` or `plugins/soleur/docs/pages/legal/**` path
  is in the diff, so the five #7387 gates do not fire. O1 is kept out of this PR for that reason.
- **Step 5 is not attested.** No marker and no sentence in this file says step 5 discharged anything.

## Drift table

| # | Claim in the record | Checked against (by function or constant name) | Verdict |
|---|---|---|---|
| D1 | No unpinned arm remains in the app | `git-auth.ts`: `TOFU_FALLBACK_OPTS` is gone; `gitDataHostKeyTrust` takes a string and refuses anything that does not match `GIT_DATA_HOST_KEY_PIN_RE`, checking `typeof` first; Guard 1 no longer allow-lists `git-auth.ts` | **Holds** |
| D2 | An absent pin refuses whatever the flag says | `resolveGitDataHostKeyPin` returns a string or throws; the absent case throws unconditionally, and its message only names the flag state | **Holds** |
| D3 | An erasure refuses before any dial and returns `unconfigured` with detail `pin_absent:` or `pin_invalid:` | `removeGitDataRepo`: the resolver guard sits outside the ssh `try`, and the reason word is `pin_invalid` or else `pin_absent` | **Holds** |
| D4 | An armed container booting without a pin reports `pin_absent_at_startup` | `logGitDataHostKeyPinAtStartup` together with `gitDataArmedInProcess` (remove key, provision key or `GIT_DATA_SSH_HOST` non-empty after trim); message path; no identifier carried. Paging for it is #8572, still open | **Holds** |
| D5 | Before merge, the erasure report reached Sentry without its tags | `reportSilentFallback` calls `logger.error` before `Sentry.captureException`; `mirrorToSentry` captures the same Error with only `feature=pino-mirror`; `redactErrorForEmit` returns the same instance when nothing is redacted; `@sentry/core` `checkOrSetAlreadyCaught` then drops the second capture | **Holds**, and corrects parent D8 |
| D6 | After merge, the outcome report's tags reach the alert, which fires per Sentry issue | `deleteAccount` calls `reportSilentFallback(null, …)` with the status leading the message; `sentry_alert.art17_erasure_incomplete` triggers on first seen, reappeared or regression and filters on `feature` and `op` | **Holds**; the outer catch is still affected (O2) |
| D7 | Ledger row flipped | The `web-1 app container -> git-data sshd` row at 2bd35fdaff reads `cert_verification` on with no `exception`; its `tls` and `does_not_defend` text matches the plan's Encryption Posture block | **Holds** |
| D8 | ADR-237 addendum exists and nothing earlier is edited | The heading "Addendum — PR #9096 (#5914): the transitional app arm is deleted" is present; `git diff --numstat` shows 0 deletions for ADR-237 and ADR-220 | **Holds** (see O3 on tense) |

> **Superseded 2026-09-28 (#8572): D4, as to "Paging for it is #8572, still open", and D6, as to "fires per Sentry issue" and "first seen, reappeared or regression".**
> Both fire on the merge of the #8572 PR together with a green `apply-sentry-infra.yml` run and a green
> `web-platform-release.yml` run after it. If either run fails, both rows stand as written. D4: `pin_absent_at_startup`
> is then paged by `sentry_alert.git_data_host_key_pin_fault`, which matches the `pin_fault` tag that only
> `reportGitDataPinFault` writes, at most once per issue per 4 hours. D4's claim itself still holds. D6:
> `sentry_alert.art17_erasure_incomplete` then also triggers on every event (`event_frequency_count {1h, 0}`),
> throttled by `frequency_minutes = 5`: at most one email per issue per 5 minutes, never one per refusal. Its
> `feature` and `op` filters are unchanged. The rows are not edited. See the addendum at the end of this file.

## Processors, recipients, data categories

No new processor, recipient, transfer or category of personal data. The pin is a host public key,
and the startup line carries only its fingerprint; neither is personal data. `pin_absent_at_startup`
carries no identifier. Moving the outcome report to the message path changes which Sentry field
holds the existing `gitDataRepoId` value: it moves from a breadcrumb's data to `extra`. It does not
add a recipient. O1 records the disclosure gap that existed before this PR.

## Per-artifact verdict

| Artifact | Verdict |
|---|---|
| Register: PA-36 (g)(14) activation marker | **APPROVED.** A past fact on the item's own criterion, with no present-tense claim over personal data. |
| Register: PA-36 (g)(14) residual (b) and alert marker | **APPROVED.** The past fact and the part that depends on the merge are kept separate, and the ledger flip is named. |
| Register: PA-1 (g)(14) and PA-2 (g)(18) markers | **APPROVED.** The two are twins, and the relay description is not amended. |
| Register: PA-36 (g)(2) (#8629) marker | **APPROVED.** It corrects two sentences that were false in production. |
| `scripts/encryption-posture-ledger.json`: the row above | **APPROVED.** |

## Disposition

**DISCHARGED, conditioned on the merge of PR #9096, subject to C1 and C2.** Once both are met, the
ship Phase 5.5 CLO-Attestation gate for PR #9096 is satisfied. The step-5 discharge record is a
separate merge precondition (G1) and is not attested here. The operator retains an optional veto.

## Addendum (2026-09-28, #8572)

**Condition.** This addendum fires on the merge of the #8572 PR together with a green
`apply-sentry-infra.yml` run and a green `web-platform-release.yml` run after that merge. If the PR
closes unmerged or either run fails, nothing in this addendum holds, and the record above stands as
written. A later evidence-only PR will append the run ids. This addendum does not claim that
verification. Nothing above it is edited.

- **What changes.** A new Sentry rule, `git-data-host-key-pin-fault`, matches the `pin_fault` tag
  (`host_key_mismatch`, `pin_absent`, `pin_invalid`, `ssh_client_absent`). Only
  `reportGitDataPinFault` writes that tag, on Sentry's message path. The rule covers the three boot
  reports and a replication push that is refused on the pin. It triggers on first seen, reappeared,
  regression and every event. It emails issue owners, falling through to active members, at most
  once per issue per 4 hours (`frequency_minutes = 240`). Before `GIT_DATA_STORE_ENABLED` is set,
  only the boot reports can fire. Rule `art17-erasure-incomplete` gains the every-event trigger. Its
  filters are unchanged, and its throttle is `frequency_minutes = 5`. The erasure report is not
  tagged `pin_fault`, so one refusal sends one email, not two.
- **Re-evaluation trigger (1): HALF DISCHARGED.** #8572's paging condition is met on the merge and
  both green runs. #8211's per-id re-erasure path still stands. It is a hard precondition for the
  first `GIT_DATA_STORE_ENABLED` flip, and a flip before it is a hard block. The
  `re_evaluation_triggers` value above is not edited. Read it with this addendum.
- **Re-evaluation trigger (2): paged, not pulled.** Each event the trigger names now reaches the
  operator by email instead of only by a query. A `pin_absent:` or `pin_invalid:` erasure outcome
  pages through `art17-erasure-incomplete`, at most once per issue per 5 min and never per refusal.
  A `pin_absent_at_startup` event pages through `git-data-host-key-pin-fault`, at most once per issue
  per 4 h. The trigger itself does not change, and neither do the Art. 12(3) clock and the
  clo-attestation issue routing. The clock still starts by hand from the first event (#9153 would
  start it automatically). The pull is not retired: a pin fault that recurs within 4 h of a resolve
  is silent under the 240-minute interval, so the runbook's `pin_fault:*` query still covers that
  window.
- **Processors, recipients, data categories.** No new processor, recipient, transfer or data
  category. Sentry is already a processor for these events. The push report carries only these
  fields:
  - hashed workspace and worktree ids;
  - the lease generation;
  - the user id, pseudonymised by `reportSilentFallback` (`userIdHash`);
  - `via` and the fault.

  It sends no stderr and no error message. The capture runs in a fresh isolation scope with
  breadcrumbs cleared.
- **Not addressed here (deferred).** Unifying the erasure and push classifiers (#9152). Starting the
  Art. 12(3) clock automatically (#9153). Raw ids in the non-pin push Error-path message, which is
  pre-existing and unchanged (#9154). The raw `gitDataRepoId` in the erasure extra, which is O1 and
  pre-existing (#9121).
- **Register markers attested.** The three 2026-09-28 (#8572) markers in PA-36 (g), each on the
  condition above:
  - in (2), after "...not per refusal.";
  - in (14), after "...which no alert routes until #8572.";
  - in (14), after the ledger-flip sentence ending "the transitional app arm is deleted").".

  **APPROVED.** Each quotes the words it supersedes and deletes none.

**Disposition of this addendum: DISCHARGED, on the condition above.** The operator retains an
optional veto.
