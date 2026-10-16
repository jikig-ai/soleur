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
| `docs/legal/acceptable-use-policy.md` + mirror, 5.8 | DISCHARGED, no change | States what is recorded, that no summary is available to owners or members, that toggle-off does not delete records. Adds no use restriction. Cosmetic only: "a longer-lived operator-side copy" reads against a summary that does not exist yet; not misleading, left as drafted. |
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
