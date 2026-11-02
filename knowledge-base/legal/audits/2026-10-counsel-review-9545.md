---
title: "Counsel review audit — #9545 PR1 / PR #10349 (dark egress audit rollup: Privacy Policy 4.7/7, AUP 5.8, DPD 2.3(ag), GDPR Policy 3.16/8.4/9/10, Art. 30 PA-2/PA-8/PA-37/P-3)"
type: counsel-review
date: 2026-10-15
issue: 9545
pr: 10349
status: "SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)"
signed_off_at: 2026-10-15
signed_off_by: "CLO agent (independent reviewer; a different CLO instance drafted the wording). Attestation authority for the Soleur-as-tenant-zero v1 posture; the operator retains an optional veto."
disposition: "DISCHARGED for the PR1 merge, with conditions C1-C3 applied in this review. DISCHARGED covers the public text as a description of a DARK pipeline. It does NOT discharge any open counsel item, and it does NOT authorise enabling collection, publication or the merge itself: those stay with the user."
conditions:
  - "C1 — Dark-state overstatement. The text said collection is 'off' for every external workspace without saying that the gateway host still tallies those workspaces' decisions in memory and a short-lived local buffer and the app discards them after the per-organisation flag check. Nothing is stored, but 'off' was read as 'not processed'. Sentence added to Privacy Policy 4.7 (2), GDPR Policy 3.16(b) and DPD 2.3(ag), canonical and mirror."
  - "C2 — Team-workspace role stated as settled. The public documents stated 'Jikigai is processor' for a team workspace as fact while the record holds it as drafted, not settled (P-3 reserved; zero customer DPAs on record; Jikigai chose fields, retention and purpose). Qualifier added in Privacy Policy 4.7, GDPR Policy 3.16 Roles and section 10 item 12, and DPD 2.3(ag): a working position, still being confirmed, text to be updated first, no such collection today. GDPR 3.16 'Lawful basis ... for both (a) and (b)' narrowed to (b) in a solo workspace so it no longer contradicts the Roles paragraph."
  - "C3 — Stale register cell. Art. 30 PA-37 (g) still said the pre-authentication 403 residual was 'not yet measured' after the DPIA addendum 11.8 measured it. Corrected in-cell, with a Superseded marker under the cell and under DPIA addendum 11.7 item 5."
pr2_signoff: "SIGNED-OFF 2026-10-26 (CLO-agent-attested, Soleur-as-tenant-zero v1) for the PR2 strings at HEAD 8567d8f2a1fa652f4b722d93dc36164ea9c19646 of PR #11115 (#9545 PR2), on S1-S6 met in verification pass 2; conditional on the merge of that PR and covers the strings and documents read at that HEAD (plus the CLO legal-document edits of pass 2, uncommitted when read) and nothing else. It does not discharge any open counsel item and does not authorise enabling collection (S7 and #11237 stay open). Pass 1 (HEAD 5a9d81c0) was BLOCKED on S5; closed by pass 2."
re_evaluation_triggers: "Any of: the flag egress-audit-collection is switched on for any workspace; PR2 (member SELECT policy and read route) is proposed; first non-Jikigai team workspace; first arms-length Workspace Owner; first EEA-out operator; first regulated-industry tenant; the retention number changes (re-screening trigger t7); any user, session, IP, client-address or path field is added to the table, ingest payload, Vector rollup or read route; a Squid version change (re-measure the pre-auth 403 paths)"
related:
  - knowledge-base/legal/audits/2026-10-15-dpia-screening-addendum-egress-audit-rollup.md
  - knowledge-base/legal/audits/2026-10-05-dpia-screening-agent-web-egress.md
  - knowledge-base/engineering/architecture/decisions/ADR-288-aggregated-egress-audit-spool-via-vector-to-app-ingest.md
  - knowledge-base/engineering/operations/runbooks/egress-audit-enable.md
  - knowledge-base/engineering/operations/runbooks/egress-audit-dsar.md
---

# Counsel review audit — #9545 (dark egress audit rollup)

Load-bearing evidence for the ship-time Counsel-Review CLO-Attestation Gate on PR #10349. Under the Soleur-as-tenant-zero v1 posture the CLO agent performs this review. This is the v1 internal sign-off, not external counsel review; the open items below are what external counsel is for. Verdicts are conditional on the merge of the PR that carries the change; nothing here is evidence that collection is happening, because it is not.

## Code and facts cross-checked (by name)

- `apps/web-platform/supabase/migrations/162_workspace_egress_audit_rollup.sql` — table, nine columns, RLS enabled with no policy, `REVOKE ALL` from `anon`/`authenticated`; `ingest_egress_audit_rollup` (service role only, toggle checked at ingest, orphan-workspace skip under `FOR SHARE`, per-bucket row cap with an `(other)` fold, `GREATEST`/`LEAST` merge); `purge_egress_audit_rollup` (30 days on `last_seen`, daily `egress-audit-rollup-retention` job at 04:30 UTC); `erase_egress_audit_rollup` (orphan only) and `erase_egress_audit_rollup_for_requester` (sole member, refuses while `web_egress` is on).
- `apps/web-platform/server/egress-audit-ingest.ts` — loopback and proxy-marker check, bearer with previous-token rotation, refusal when the global env mirror of the flag is on in production, per-row zod, bucket bounds, workspace-to-organisation lookup, flag evaluated per organisation and fail-closed, then the RPC. Reject and error mirrors carry reason codes and counts.
- "Egress audit rollup" section of `apps/web-platform/infra/vector.toml` — positive status allowlist (200, 403, 502, 503, 504), UUID workspace filter, host character allowlist, `decision` normalised to allowed/denied/other, 1,000-per-workspace and 5,000 keyless throttles, 15-minute reduce, disk-buffered http sink, the two marker lines.
- ADR-288 (status `adopting`, moves to accepted only after PR2 and the 7-day notice) and the two runbooks.

## Drift table (prose against code)

| Public claim | Code evidence | Verdict |
|---|---|---|
| Rollup stores nine fields; no resolved IP, client address, duration, user, session or path | Table definition and `egress_audit_prep` output object | MATCH |
| Retention "about 30 days, up to about 31", a proposal; daily sweep | `purge_egress_audit_rollup(interval '30 days')` on `last_seen`, cron `30 4 * * *`; bucket-age check at ingest | MATCH |
| Nobody can read it in the product | RLS on, no policy, `REVOKE ALL` | MATCH |
| Collection off for every workspace but a Jikigai-owned canary; default off | `FLAG` evaluated per organisation, fail-closed on error; env-mirror refusal in production | MATCH, but see C1 |
| Switching Agent web access off stops new records; buffered events dropped; existing rows kept | `v_toggle IS NOT TRUE` skips at ingest; purge is the only deletion | MATCH |
| Failed login, aborted connection, non-workspace name and health-check name never reach the database | Status allowlist and UUID filter in `egress_audit_prep` | MATCH |
| A workspace with no member is skipped; solo-account erasure removes the rollup | Orphan skip in the RPC; saga step 5.15 `erase_egress_audit_rollup` | MATCH |
| Counts are lower bounds; host set exact only below a cap | `GREATEST` merge, restart loses partial buckets, 500 row cap, 1,000 event throttle | MATCH |
| Operator-side log holds IP, client, duration, reason code, status, bytes; 90 days; failed-auth attempts included | DPIA addendum 11.4; Better Stack path unchanged | MATCH (taken from the addendum; the Better Stack envelope itself is outside this diff) |
| Marker lines: per-workspace one carries a workspace id (personal data for a solo workspace), global one a count | `egress_audit_throttled_marker` / `_global_marker` | MATCH |
| "Collection is off" for external workspaces | Vector tallies every workspace's decisions and POSTs them; the app drops after the flag check; nothing stored | UNDERSTATED before C1; fixed |
| Jikigai is processor in a team workspace | No Art. 28(3) instrument; fields, retention, purpose chosen by Jikigai | OVERSTATED as settled before C2; fixed by qualifier. The question itself is OPEN |

## Per-artifact verdicts

| Artifact | Verdict | Note |
|---|---|---|
| `docs/legal/privacy-policy.md` + mirror, 4.7 and 7 | DISCHARGED (C1, C2 applied) | Accurate for a dark pipeline. Dated, temporal, conditional. Corrects the older "destination and workspace attribution only" sentence and limits "withdraws consent" to the capability. Art. 21 route is stated. |
| `docs/legal/gdpr-policy.md` + mirror, 3.16, 8.4, 9, 10 | DISCHARGED (C1, C2 applied) | Balancing test marked provisional, standalone LIA disclosed as owed, DPIA status stated as provisional with criterion 3 named. Section 10 item 12 now carries the role qualifier. |
| `docs/legal/data-protection-disclosure.md` + mirror, 2.3(ag) | DISCHARGED (C1, C2 applied) | Two stores separated; Sentry-fragment caveat present. |
| `docs/legal/acceptable-use-policy.md` + mirror, 5.8 | DISCHARGED, no change | States what is recorded, that no summary is available to owners or members, that toggle-off does not delete records. Adds no use restriction. Cosmetic only: "a longer-lived operator-side copy" reads against a summary that does not exist yet; not misleading, left as drafted. **Superseded 2026-10-26 (#9545, PR2), as to "a summary that does not exist yet" and "no summary is available to owners or members":** PR #11115 (draft at the date of writing) adds the member audit view, and AUP 5.8 and the other public texts are amended to say so; the PR2 wording is not covered by this attestation and needs its own CLO sign-off (AC10 of the PR2 plan), and this row's PR1 verdict is left as written. |
| `knowledge-base/legal/article-30-register.md` (PA-2/PA-8 amendments, PA-37) | DISCHARGED (C3 applied) | Append-only discipline followed; PA-37 conditional throughout. |
| `knowledge-base/legal/article-30-2-register.md` (P-3 reserved) | DISCHARGED | Correctly reserved, not opened; trigger and owed instrument named. |
| `knowledge-base/legal/audits/2026-10-15-dpia-screening-addendum-egress-audit-rollup.md` | ACCEPTED AS A SCREENING RECORD | Not an attestation of anything public. Provisional "no full DPIA" holds on the facts as built. Marker added under 11.7 item 5. |
| `knowledge-base/legal/compliance-posture.md` | DISCHARGED | The five new Active Items rows keep the open items open and gate ENABLING, not merging. |
| `docs/legal/terms-and-conditions.md` | NOT TOUCHED | No T&C or `TC_VERSION` change was made and I found none that the PR1 text forces. That is an observation, not a closure of open item 7. |

## Open counsel items (all stay OPEN; none is resolved by this attestation)

1. Team-workspace controller versus processor characterisation, the Art. 28(3) instrument if processor, and a standalone legitimate-interest assessment. Owed before collection for the first non-Jikigai team workspace.
2. The retention number: 30 days (about 31 in practice) is proposed, not approved. Gates enabling.
3. Art. 21 sufficiency: whether toggle-off plus the DSAR route is enough given toggle-off leaves records in place.
4. WP248 criteria 3 and 7 at the PR2 re-screen, and the supervisory authority's Art. 35(4) list (unverified). A full DPIA stays a live outcome.
5. Marker-line and Sentry-fragment coverage under the existing PA-8 and Sentry entries. Observation added by this review: for a workspace with collection off, the per-batch flag evaluation still presents the organisation identifier (personal data for a solo workspace) to Flagsmith, an existing processor; confirm the existing Flagsmith entry covers it.
6. Whether any T&C change or `TC_VERSION` bump is owed (item 7 of the addendum).

(The former pre-authentication 403 residual is closed as an engineering fact, addendum 11.8; re-measure on a Squid change.)

## Boundary of this attestation

- Gates the PR1 merge only as to the accuracy of the public text for a dark pipeline. ENABLING collection for any workspace, publication of the text, and the merge remain the user's decisions. `egress-audit-enable.md` already makes the counsel items a precondition for any external workspace ("resolved or accepted"); the operator should name items 1 to 6 explicitly when taking that decision.
- The commitment in the public text of at least 7 days' owner notice by email and in the product before external enablement is a binding promise; PR2 or the operator must deliver it before the flag moves.
- The verbatim-code check covered the migration, the ingest handler and the Vector section. Better Stack's own retention setting and the gateway log field list were taken from the DPIA addendum, not re-verified against a live system.

> **Note 2026-10-26 (#9545, PR2).** The re-evaluation trigger "PR2 (member SELECT policy and read route) is proposed" in the frontmatter has fired: PR #11115 (draft at the date of writing) proposes the member audit view. The PR2 mechanism differs from the trigger's wording (a membership-checked `SECURITY DEFINER` function; no member policy, no route). This attestation covers the PR1 public text for a dark pipeline only and is not extended to the PR2 wording of Privacy Policy 4.7/7, AUP 5.8, DPD 2.3(ag) and GDPR Policy 3.16/8.4/9, the view banner or the enable-dialog recording notice. Those need their own CLO sign-off (AC10 of the PR2 plan); the DPIA t6 re-screen they rest on is `2026-10-15-dpia-screening-addendum-egress-audit-rollup.md` section 12. The frontmatter and verdicts above are left as written.

## PR2 (#11115) sign-off requirements (added 2026-10-26; SIGNED-OFF 2026-10-26 at HEAD 8567d8f2, see Verification pass 2)

**Status: SIGNED-OFF 2026-10-26 at HEAD 8567d8f2 (verification pass 2, below; pass 1 was BLOCKED on S5; before that PENDING).** The sign-off covers the PR2 wording as read at HEAD 8567d8f2 (verification pass 2); a verdict on any earlier string would have attested to text that does not ship, and a later change to a string listed below needs a new pass. AC10 of the PR2 plan (CLO sign-off of the view copy and dialog notice as a merge condition) is discharged by pass 2, subject to the merge of PR #11115. The verdict was recorded in this section after the lead returned the final strings and the CLO verified them against the list below. The attestation is conditional on the merge of PR #11115 and is not evidence that collection happens: the flag is not flipped by this PR (#11237). It does not discharge any open counsel item.

> **Superseded 2026-10-26 (#9545, PR2), as to "No sign-off is recorded for the PR2 wording", "AC10 ... stays open" and "When the lead returns the final strings ..." in the paragraph above:** replaced in-cell; pass 1 (HEAD 5a9d81c0) was BLOCKED on S5 and pass 2 (HEAD 8567d8f2) signed off.

### Texts the CLO must see (file, then the strings)

1. `apps/web-platform/components/settings/web-egress-toggle.tsx`
   - `RECORDING_NOTICE`, verbatim as ruled: "Hosts your agents contact are recorded as best-effort summary counts: the host, whether the request was allowed, blocked or ended another way, and the number of requests. Every current member of this workspace can view them, including activity from before they joined. No member or session is recorded, some entries may be missing, and counts are minimums. Records are deleted about 30 days after they were recorded. Turning web access off stops new records but does not delete existing ones."
   - The "unknown" composition: "We couldn't check whether recording is on for this workspace. If it is, the following applies. " followed by `RECORDING_NOTICE` itself (one constant; no second sentence of its own, and the old generic sentence "Activity may be recorded and visible to members of this workspace." removed).
   - Render condition: dialog notice when `collection === true` (full) or `"unknown"` (conditional lead + full); nothing when `collection === false`.
   - Card note, for every role (not only non-owners), when `collection !== false`: true "Activity through web access is recorded for this workspace and visible to every current member." / unknown "Activity through web access may be recorded for this workspace and visible to every current member."
   - Off-state line "Existing records stay visible to members until deleted about 30 days after they were recorded." and the "Last recorded request: N ago" hint.
   - The enabled-state sentence "turning off revokes live access on the session's next dispatch".
2. `apps/web-platform/components/settings/egress-audit-view.tsx`
   - Banner `lead` ("A best-effort summary, not a full record.") and `body` as ruled: "Some requests may be missing and counts are minimums. Every current member of this workspace can see this list, including activity from before they joined. No member or session is recorded. Records are deleted about 30 days after they were recorded."
   - The Other explainer as ruled: "Other: the request was neither allowed through nor blocked by policy, for example because the destination returned an error."
   - Filter labels (Allowed, Blocked, Other), every empty, off and error state body that mentions retention, the footer link (`https://soleur.ai/legal/privacy-policy/#data-subject-rights`) and its anchor text, and the time cell markup (no `title`, no absolute time).
3. `apps/web-platform/server/egress-audit-read.ts`: the card loader returns `collection: "unknown"` on any failed organisation lookup, failed flag read or Flagsmith outage; only a successful read returning off is `false`.
4. The eight legal files (Privacy Policy, GDPR Policy, Data Protection Disclosure, Acceptable Use Policy, canonical and mirror), `legal-doc-shas.ts`, the DPIA addendum sections 12 and 13, and the Art. 30 register amendments, as edited by the CLO on 2026-10-26.

### Conditions of sign-off

- **S1. Strings identical to the rulings.** The shipped strings match the list above character for character, or differ only in ways the CLO has seen and accepted. A test pins `RECORDING_NOTICE` and the "unknown" composition so a later edit fails CI.
- **S2. Forbidden words.** None of "complete", "every connection", "tamper-proof", "sessions" (plural) appears in any user-facing string of the card, dialog, banner, explainer, empty or error states. "about 30 days" appears wherever retention is stated in product copy; "exactly 30" and a calendar date never do.
- **S3. Collection state.** A Flagsmith outage reads `"unknown"`, not `false` (S1 test and a unit test on the loader).
- **S4. All roles.** The card note renders for owners and members alike when `collection !== false`.
- **S5. No clock time.** The time cell has no `title`, tooltip or absolute time; the card and view show relative age only (DPIA addendum C7).
- **S6. Mirrors and pins.** `check-tc-document-sha.sh` and `lint-legal-mirror-drift-baseline.sh` exit 0 after the final edit, and the canonical and mirror prose agree on every sentence changed on 2026-10-26.
- **S7. Pre-flip check (tracked on #11237, not a merge condition).** Before the flag moves for any external workspace: the deployed product shows all three surfaces for all roles; `https://soleur.ai/legal/privacy-policy/` carries the 2026-10-26 text; the 7-day owner notice has gone out; the team-workspace capacity determination (DPIA addendum 13.1), the retention approval and the standalone LIA exist.

### Rulings made on 2026-10-26 that the sign-off rests on

F1 and F16: the owner-dialog and card statements in the public texts are conditional on recording being on or unverifiable, and the card note is shown to every role. F2 and F9: one constant, three states. F3: the team-workspace capacity is an explicit pre-flip decision and the public texts say Jikigai may be a controller. F4: timing linkability is a named residual and the hover time is removed. F7: "visible for 30 days after they were recorded and deleted within about a day after that" in the legal texts. F8: turning web access off revokes live access from the next dispatch, not instantly. F10: the card's last-request display is disclosed. F11: permalink. F17: no temporal qualifier in the permanent text; the deploy-order control is S7. Full reasoning: DPIA addendum section 13.

### Verification pass 1 (2026-10-26, HEAD 5a9d81c02dcc8e49a8f520ec1a6f1ff1167cbb13): BLOCKED on S5

Read at that HEAD: `web-egress-toggle.tsx`, `egress-audit-view.tsx`, `egress-audit-read.ts`, `egress-audit-collection.ts`, `readRuntimeFlagDetailed` in `lib/feature-flags/server.ts`, `WEB_EGRESS_PROMPT_ADDENDUM` in `cc-dispatcher.ts`, the added lines of the four legal documents (canonical against mirror), the DPIA addendum sections 12 and 13. Ran `vitest run test/web-egress-toggle.test.tsx test/egress-audit-view.test.tsx test/egress-audit-read-loader.test.ts` (3 files, 109 tests, exit 0), `check-tc-document-sha.sh` (exit 0), `lint-legal-mirror-drift-baseline.sh --base origin/main` (exit 0) and `lint-legal-scope-block-placement.sh --base origin/main` (exit 0). This pass attests to nothing outside that HEAD.

| Condition | Result | Evidence (by name) |
|---|---|---|
| S1 strings identical | MET, one non-blocking gap | `RECORDING_NOTICE`, `RECORDING_NOTICE_UNKNOWN` (template: the "couldn't check" lead, then the one constant), `CARD_NOTE`, banner `lead`/`body` in `Banner`, the Other explainer in `Chips`, the off-state line and `PRIVACY_RIGHTS_URL` match the rulings character for character. The tests pin each of the five sentences of the notice and the unknown composition by `toContain`; an extra sentence inserted between them would not fail CI. Hardening requested, not a condition. |
| S2 forbidden words | MET on the reading below | No "complete", "every connection", "tamper-proof" or "exactly 30" in any recording or audit string. "about 30 days" is the form wherever retention is stated. The window phrases "in the last 30 days" / "30-day window" describe the query window (F7: visible 30 days after recording), not retention, and are accepted. The plural "sessions" appears only in two pre-existing access-scope sentences on the card ("outbound access for agent sessions", "Applies to sessions started after enabling"). They describe which sessions get web access and say nothing about recording; S2's purpose is to keep session-level recording language out, so they are accepted. The tests apply the forbidden-word pattern to the recording strings only. |
| S3 collection state | MET | `readCollection` returns `"unknown"` on a timed-out, errored, empty or thrown organisation lookup (`org_read`) and on a timed-out or thrown flag read (`flag_eval`); `readEgressAuditCollectionState` returns `"unknown"` when `readRuntimeFlagDetailed` reports `fellBack` (the Flagsmith fetch failed and the env-mirror snapshot was used). `loadEgressCardState` returns `"unknown"` on its overall bound and on any throw. Loader tests and `egress-audit-flag-detailed.test.ts` cover it. Residual noted: with no Flagsmith key configured `fellBack` is false by design; production has the key. |
| S4 all roles | MET | The card note renders when `collection !== false` with no role condition; the test iterates both roles. The scope-grants page passes `collection` from `loadEgressCardState` and defaults to `"unknown"`. |
| S5 no clock time | NOT MET | `TimeText` in `egress-audit-view.tsx` renders `<time dateTime={iso}>`. The `dateTime` attribute carries the full ISO timestamp (minute resolution and finer) on every time cell. It survives save-page, copy and a screenshot of the inspector, which is the persistence addendum 13.2 removed the `title` for; S5 says "no ... absolute time" on the time cell. The existing test checks only `time[title]`. The `title` is gone; the `dateTime` is not. Fix: drop the element's `dateTime` (exact text in the hand-back). |
| S6 mirrors and pins | MET | SHA check exit 0; drift baseline exit 0; the added lines of the four canonical documents equal the mirror's added lines apart from the mirror's own "Last Updated" display line (and the canonical `last-updated` frontmatter in the AUP). The drift script prints that the #7465 remediation target (2026-09-30) has passed with 80 drift lines remaining: pre-existing, not caused by this PR, still owed. |
| S7 pre-flip | OPEN, not a merge condition | Tracked on #11237. See the gates below. |

Non-blocking, requested alongside the S5 fix: (a) `WEB_EGRESS_PROMPT_ADDENDUM` calls the gateway "audited"; the following sentence correctly limits the claim to best-effort recording, but an agent can relay "audited" to a user, so replace "a dedicated, audited gateway" with "a dedicated egress gateway". (b) Add an exact-equality test of the full dialog notice. (c) The card's `lastRequestAt` prop is an ISO string in the page payload so the client can compute the relative age after mount: accepted as transport of the same datum that every member can already obtain from the RPC, not displayed, not exported; revisit if the card ever shows or stores it.

Enablement-time gates still open on #11237 (unchanged by this pass): the 7-day owner notice (at least 7 days live before any external flip); the team-workspace controller-capacity determination (DPIA addendum 13.1) with an Art. 28(3) instrument if processor and the standalone LIA; the retention approval; Art. 21 sufficiency; operator authorisation to flip.

> **Superseded 2026-10-26 (#9545, PR2), as to "BLOCKED on S5" and "the verdict below replaces this paragraph's BLOCKED status":** the S5 fix landed at HEAD 8567d8f2 and was re-verified in pass 2 below; the pass 1 table is left as the record of what was found at HEAD 5a9d81c0.

### Verification pass 2 (2026-10-26, HEAD 8567d8f2a1fa652f4b722d93dc36164ea9c19646): SIGNED-OFF

Re-read at that HEAD: the diff of the components, server and lib files since 5a9d81c0 (`TimeText`, `UnavailableCard`, `WEB_EGRESS_PROMPT_ADDENDUM`, `readCollection` and its per-op messages, `readEgressAuditCollectionState`, the refresh button) and the test diffs. Ran `vitest run test/web-egress-toggle.test.tsx test/egress-audit-view.test.tsx test/egress-audit-read-loader.test.ts` (3 files, 115 tests, exit 0); after the pass 2 legal edits below, `check-tc-document-sha.sh` (exit 0), `lint-legal-mirror-drift-baseline.sh --base origin/main` (exit 0), `lint-legal-scope-block-placement.sh --base origin/main` (exit 0) and `legal-doc-consistency.test.ts` (37 tests, exit 0).

| Condition | Result | Evidence (by name) |
|---|---|---|
| S1 | MET | `RECORDING_NOTICE`, `RECORDING_NOTICE_UNKNOWN`, `CARD_NOTE`, banner and explainer unchanged and identical to the rulings. The tests now pin the dialog notice and the unknown composition by whole-string equality against literals copied from this file (`RULED_NOTICE`, `RULED_UNKNOWN`), and the card notes by `textContent` equality. The pass 1 gap (an inserted sentence would not fail CI) is closed. |
| S2 | MET | No forbidden word in any recording or audit string, including the reworded `UnavailableCard` body (it no longer says anything about deletion and states no retention). Ruling on the plural "sessions": accepted, see below. |
| S3 | MET | `readCollection` unchanged in logic (only the per-op messages differ); `"unknown"` on a failed, timed-out, empty or thrown org lookup and on a failed or timed-out flag read; `readEgressAuditCollectionState` maps `fellBack` to `"unknown"`; `loadEgressCardState` returns `"unknown"` on its overall bound. The component comment now also lists the pointer fault and the page's workspace-mismatch override as `"unknown"` causes. |
| S4 | MET | Card note renders on `collection !== false` for every role; tests iterate owner and member. |
| S5 | MET | `TimeText` is `<span>{formatAgo(iso, now)}</span>`; no `<time>`, no `dateTime`, no `title` on a time cell. The view tests assert, for every state, `document.querySelector("time")` is null and `document.body.innerHTML` has no ISO stamp. The card's `lastRequestAt` prop remains transport only (pass 1 item c). |
| S6 | MET | SHA check, drift baseline, scope-block lint and the heading-parity test all exit 0 after the pass 2 legal edits, with `legal-doc-shas.ts` re-pinned for the three edited canonical documents. The added lines in the canonical and mirror documents agree (the mirror's own "Last Updated" display line aside). The #7465 remediation-target warning from the drift script is pre-existing and still owed. |
| S7 | OPEN | Not a merge condition; tracked on #11237. |

`WEB_EGRESS_PROMPT_ADDENDUM` now says "a dedicated egress gateway": the pass 1 item (a) is closed.

Rulings made in pass 2 (legal-auditor P3s):

- **(a) Basis if Jikigai is a controller.** The public Roles text said the Workspace Owner's organisation determines the basis and Jikigai "does not claim an Article 6 basis of its own", while DPIA 13.1 records that Jikigai claims Art. 6(1)(f) for the rollup in every workspace. These are reconciled by a conditional sentence, not by dropping the processor position (which stays a working position): if Jikigai is a controller of the team-workspace rollup, alone or jointly, its basis is Article 6(1)(f), as for a solo workspace; it claims no basis of its own only to the extent that it acts purely as a processor. Applied to GDPR Policy 3.16 (the "Lawful basis" heading line and the Roles paragraph), DPD 2.3(ag) and Privacy Policy 4.7 (Roles and legal basis). Privacy Policy 4.7 "Your rights", which said the rollup "rests on legitimate interest" for all workspaces, now says the operator-side log rests on legitimate interest and the rollup does so wherever Jikigai is its controller (a solo workspace, and a team workspace if Jikigai is a controller of it), with the Article 21 route unchanged. Canonical and mirror edited together; `legal-doc-shas.ts` re-pinned. This is a public-text clarification only; it asserts no collection and no new processing.
- **(b) Art. 30 register PA-2 / PA-37.** The cells are *living text*: Art. 30(1) requires the record to describe the processing as it stands, and the cells were corrected in place (the 2026-10-26 corrections follow this review's own in-cell rule) because several superseded sentences were false statements of present fact (for example "no member can read the table" and "nothing readable"). Restoring the old wording would put those false statements back into the operative record. What the rule requires is that the replaced wording stay recoverable, and the earlier markers named the cells but did not quote them. A verbatim ledger of the replaced PA-37 wording is now appended under the markers in `article-30-register.md`; the 2026-10-15 text is also in git at the merge of PR #10349. The PA-2 amendment keeps its own marker. No register cell is to be edited in place again without a marker quoting the replaced sentence.
- **(c) `compliance-posture.md`.** The older Active Items row that still said "processor for team workspaces with no Art. 6 basis claimed in that capacity" is qualified in-cell (working position; Jikigai may be a controller, basis Art. 6(1)(f) if so) with a Superseded marker; it now agrees with the team-workspace row and the t6 row.
- **(d) Plural "sessions" in the two card strings.** Confirmed against `origin/main:apps/web-platform/components/settings/web-egress-toggle.tsx`: "HTTPS-only outbound access for agent sessions" and "Applies to sessions started after enabling" (and the file comment "hosted agent sessions") exist there unchanged. They state which sessions the capability reaches; they say nothing about recording. S2 is accepted as covering recording and audit strings only (the card note, dialog notice, banner, explainer, filters, empty and error states, the view heading and subtitle). The tests apply the forbidden-word pattern to those strings, which is the accepted scope.

Boundary of this sign-off: attests that the strings and documents read at HEAD 8567d8f2 (and the pass 2 legal edits) say what the rulings say and match the code; it is conditional on the merge of PR #11115; it is not evidence that collection happens; it discharges no open counsel item (items 1 to 6 above, the retention number, the team-workspace capacity decision, the standalone LIA); and the flag stays unflipped until the S7 items on #11237 are done, including the 7-day owner notice.
