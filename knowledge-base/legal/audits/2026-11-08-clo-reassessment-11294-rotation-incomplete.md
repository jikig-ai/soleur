---
title: "CLO re-assessment — #11294 rotation state at the fired 2026-11-08 trigger (determination stands, PROVISIONAL)"
type: clo-attestation
date: 2026-11-08
issue: 11294
related_issues: "10205, 11293, 11711, 11922, 12299"
attestation-authority: clo
status: "DRAFT v1 — internal CLO attestation (Soleur-as-tenant-zero v1), NOT external counsel advice. SIGNED-OFF PROVISIONAL by the CLO agent on 2026-11-08; operator retains an optional veto."
disposition: "RE-ASSESSMENT at the fired 2026-11-08 trigger: the 2026-10-29 determination STANDS — a security incident, not a presumed notifiable personal-data breach; the Art. 4(12) second limb remains not established and Art. 33/34 remain not engaged. Rotation is recorded complete for 7 of the 12 exposed values and the prd signing/event pair is retired as dead values; two printed values remain usable (the previous `egress_audit_ingest_token` value is still accepted and `github_webhook_secret` is unrotated) and `tunnel_secret` awaits the owner's decision. PROVISIONAL continues; no limb is certified clean."
disposition_history: "2026-10-29 SIGNED-OFF PROVISIONAL on open evidentiary limbs E1–E4; 2026-11-01 CLO position in the evidence record — the cleanup residual does not change the determination, re-assessment trigger set for 2026-11-08; 2026-11-08 re-assessment at the fired trigger — determination stands, next trigger set; 2026-11-08 addendum — rotation completed during the assessment window (9 of 12 complete, no printed value usable; see Addendum)."
signed_off_at: 2026-11-08
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; operator retains an optional veto)"
awareness_anchor: "2026-10-27T09:31:36Z — issue #11294 filed (unchanged from the 2026-10-29 determination)."
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "not due — unchanged. No evidence of use of an exposed key by a party outside its holders was found at this re-assessment, so no fresh 72h clock started. The re-opener is unchanged: a FRESH 72h runs from awareness of any such evidence."
open_limbs: "E1 run to its coverage limits (per-job verdict committed 2026-11-04; 686 hit run logs deleted 2026-10-31/11-01; the horizon, NOLOG, artifact and earlier-attempt residuals stand); E2 partly run for the dedicated pair (the 2026-11-02 A6 record's measured signals), not run for the remaining signals — INCONCLUSIVE; E3 no instrument, INCONCLUSIVE BY NATURE; E4 contained, not erased — the edit history of the 74 redacted bodies and 234 redacted comments stays public."
tier_classification: "Tier 1 — an internal determination record. No public document is edited, no right is narrowed, no processing is added. The mirror/SHA/heading gates are NOT engaged. No signed record is edited."
semver: "No TC_VERSION bump."
related_records: "`knowledge-base/legal/audits/2026-10-29-clo-determination-11294-random-id-log-exposure-art-4-12.md` (the determination under re-assessment); `knowledge-base/legal/audits/2026-10-31-11294-run-log-evidence-preservation.md` (the evidence record whose §CLO position carried the fired trigger); `knowledge-base/legal/audits/2026-11-02-a6-no-known-access-record-inngest-keys.md` (the second trigger source and the dedicated-pair use-signal measurement); `knowledge-base/project/specs/archive/20261104-211526-feat-one-shot-11294-11711-rotation-audit/audit-findings-11294.md` and `rotation-census-11711.md` in the same directory (the E1 per-job verdict and the per-secret readiness census)."
---

# CLO re-assessment — #11294 at the 2026-11-08 trigger

> **DRAFT v1. Internal CLO attestation, not external counsel advice.** It records the CLO
> agent's position on 2026-11-08 for the Art. 33(5) file. External counsel re-review is
> reserved for the triggers named in §If the finding flips of the 2026-10-29 determination,
> which are unchanged. It is append-only after merge (§Amendment convention).

## Verdict — the 2026-10-29 determination STANDS, PROVISIONAL. Re-assessed, not reopened

The 2026-11-08 trigger fired: rotation is not recorded complete in #11294 on this date. The
re-assessment that trigger called for is this record. Nothing found changes the determination.
No evidence of use of any exposed key by a party outside its legitimate holders has surfaced
since the 2026-11-01 CLO position — the only measured use-signal on file (the 2026-11-02 A6
record's "event key not recognized" rows) was attributed to Jikigai's own application holding
the pre-rotation key mid-rotation, a legitimate holder — so the second limb of Art. 4(12)
remains not established, no fresh 72-hour clock starts, and Art. 33 and Art. 34 remain not
engaged. What has changed is the exposure surface, which is narrower but not closed: 7 of the
12 exposed values are rotated complete and the prd signing/event pair is retired as dead
values, while two printed values remain usable — the previous `egress_audit_ingest_token`
value is still accepted because its clear leg has not completed, and `github_webhook_secret`
is unrotated — and `tunnel_secret` awaits the owner's decision on its roll-forward window.

> **Superseded 2026-11-08 (#11711):** the rotation tally in the sentence above — "7 of the
> 12 exposed values are rotated complete" and "two printed values remain usable" was the
> state at this record's 07:09Z read of #11711. Two completion receipts posted on #11711
> during the assessment window moved it to 9 of 12 rotated complete with no printed value
> usable: `egress_audit_ingest_token` COMPLETE 2026-11-08T07:24Z (run `42457579433`) and
> `github_webhook_secret` COMPLETE 2026-11-08T07:34Z (run `42458754890`). See the
> 2026-11-08 addendum.

The PROVISIONAL posture therefore continues; the matter is not ready for closure.

## The trigger and what fired it

Two committed sources set the same date:

- `2026-10-31-11294-run-log-evidence-preservation.md`, §CLO position (2026-11-01): *"if
  rotation is not recorded complete in #11294 by 2026-11-08, the CLO re-assesses. Evidence of
  use of a key starts a fresh 72h clock at once."*
- `2026-11-02-a6-no-known-access-record-inngest-keys.md`, §Not covered: *"The CLO re-assesses
  on 2026-11-08 if the remaining rotations are not recorded complete in #11294."*

On 2026-11-08 rotation is **not** recorded complete in #11294 or in the per-secret tracker
#11711. The trigger has fired and is discharged by this record.

## Rotation state, measured 2026-11-08

Read live from #11711 (issue body and dispatch-receipt comments), the `key-rotate.yml` and
`inngest-key-rotate.yml` run lists, and the 2026-11-06/11-07 completion comments. Counts,
dates and run ids only — no value was read for this record and none appears in it.

| Secret | State at 2026-11-08 | Evidence |
|---|---|---|
| `inngest_signing_key_dedicated`, `inngest_event_key_dedicated` | **Rotated complete** 2026-11-06T14:42Z (first rotated 2026-11-02; re-run after interrupted apply2 legs) | converge run `42235554025`: `apply2_ok`, `converge_ok`, `copies_equal=true`, fleet redeploy confirmed |
| `inngest_manual_trigger_secret_dev` | **Rotated complete** 2026-11-06 | run `42242126927`: `rotate_ok`, redeploy confirmed (an earlier rotation also recorded 2026-11-05, run `42114013956`) |
| `inngest_manual_trigger_secret_prd` | **Rotated complete** 2026-11-06 | run `42245887072`: `rotate_ok`, redeploy confirmed |
| `inngest_signing_key_dev` | **Rotated complete** 2026-11-06 | run `42247583939`: `rotate_ok` |
| `inngest_event_key_dev` | **Rotated complete** 2026-11-06 | run `42249175972`: `rotate_ok` |
| `kb_drift_ingest_signing_key` | **Rotated complete** 2026-11-06 | run `42250765131`: `rotate_ok` |
| `inngest_signing_key_prd`, `inngest_event_key_prd` | **Retired — dead values.** No rotation owed; the values authorise nothing | close-out is state removal, tracked at #11293 (open) |
| `egress_audit_ingest_token` | **Rotated, NOT complete — the previous value is still accepted.** The rotation applied green 2026-11-07 (run `42398284214`) but its `clear` leg failed `previous_not_cleared`; six further attempts on 11-07/11-08 each failed at a different leg or in flight, and run `42457579433` (dispatched 2026-11-08T07:08Z, carrying the clear-leg fix of #12353) also failed in flight at 2026-11-08T07:22Z, before this record was committed | #12299 diagnosis; #11711 dispatch receipts; run list |
| `github_webhook_secret` | **Not yet dispatched.** Blocked on the bounded grace-window prerequisite (#11922, open) and the `webhook_patch_ready` + `owner_step_pending` flow — the post-rotation App webhook-secret update and redelivery step is an owner act requiring the App private key | #11711 census row; #11922 open |
| `tunnel_secret` | **Not rotated — owner decision pending.** The printed value is probably not the live tunnel secret (`lifecycle { ignore_changes = [secret, config_src] }`; an inference, unverified). A real rotation is a tunnel replacement plus a web-2 rebuild, roll-forward only, and takes the deploy, CI-SSH and registry-push paths offline; end-user traffic is unaffected | 2026-10-29 determination §The fact pattern; #11711 |
| eleven `random_password` resources | **Not exposed** by this mechanism (`id` prints `none`) | 2026-10-29 determination |
| rehearsal `random_id` resources | **Ephemeral** — no rotation owed by this vector | `rotation-census-11711.md` |

<!-- -->
> **Superseded 2026-11-08 (#11711):** the `egress_audit_ingest_token` row's "six further
> attempts on 11-07/11-08 each failed at a different leg or in flight" — the dispatch
> ledger shows **four** further dispatches (`42409823622`, `42412554558`, `42413387208`,
> `42457579433`), not six, and `42457579433`'s rotation was verified COMPLETE at
> 2026-11-08T07:24Z: the run concluded `failure` on a readback that raced Doppler
> propagation while the rotation itself succeeded.

<!-- -->
> **Superseded 2026-11-08 (#11711):** the `github_webhook_secret` row's "Not yet
> dispatched. Blocked on the bounded grace-window prerequisite (#11922, open)" — the
> rotation completed 2026-11-08T07:34Z (run `42458754890`), and #11922 is a deferral, not
> a gate: the actual gate was #11923, closed 2026-11-06.

<!-- -->
> **Superseded 2026-11-08 (#11711):** the "eleven `random_password` resources" count — the
> census carries 13 rows and the live tree 15 (two minted 2026-11-07 via #12307). Not
> exposed either way.

## Evidence of use — checked, none found

The fired trigger's second clause is the one that matters most: *evidence of use of a key
starts a fresh 72h clock at once.* For this re-assessment the following were read:

- Every comment on #11294 (4 comments, 2026-11-03 to 11-05) and on #11711 (through
  2026-11-08T07:09Z). None reports a use-signal; all are status, dispatch and completion
  receipts.
- Every issue citing #11294 or #11711 filed since 2026-11-01, and a repository-wide search of
  issues created since that date for unauthorized-use terms. Nothing found. The open rotation
  trackers (#12299, the closed run_in_flight trackers #12241/#12249, the egress clear-leg fix
  #12353) record mechanical rotation failures, not use.

> **Superseded 2026-11-08 (#11711):** #12299 is listed above among the open trackers — it
> CLOSED 2026-11-08T07:24Z.

- The measured use-signal already on file: the 2026-11-02 A6 record's 85 "event key not
  recognized" rows (Better Stack, 12:59Z–13:29Z), attributed to Jikigai's own web app still
  holding the old key during the dedicated-pair rotation; 0 rows after redeploy. A legitimate
  holder, not external use.

**E2 stands INCONCLUSIVE, partly run.** The full signal suite named in the determination
(serves with no app origin, serve-route signature anomalies, unknown webhook delivery ids,
unexpected trigger-cron calls, ingest rows from unknown sources, Cloudflare connector and
audit-log reads) was run only for the dedicated pair's event-key leg. The signature-failure
alert rules that would make some of these limbs continuously instrumented are tracked at
#11928 and are open. No instrument reports use; the absence of a report is not a CLEAN.

## Limb states at the re-assessment

| Limb | 2026-10-29 state | 2026-11-08 state |
|---|---|---|
| E1 — run-log census | RUN for 17 workflows, SAMPLED for 7; closing re-pull owed | **Run to its coverage limits.** The closing per-job verdict is committed (`audit-findings-11294.md`, merged 2026-11-04 via #12105); all 686 hit run logs deleted 2026-10-31/11-01. Residuals stand as known gaps: the 90-day horizon, 16 NOLOG runs, the unscanned artifact surface, earlier attempts of multi-attempt runs |
| E2 — use-of-key signals | NOT RUN | **Partly run** (dedicated pair, 2026-11-02 A6 record); the remaining signals not run; INCONCLUSIVE |
| E3 — who viewed the logs | NO INSTRUMENT | Unchanged — **INCONCLUSIVE BY NATURE** |
| E4 — copies outside the run logs | RUN FOR ISSUES; not yet contained | **Contained, not erased.** 498 PR bot comments deleted, 74 issue bodies and 234 issue comments redacted in place 2026-11-01; their edit history stays publicly readable. The artifact surface is unscanned |

<!-- -->
> **Superseded 2026-11-08 (#11711):** the E4 row's "their edit history stays publicly
> readable" — only the **redacted** items (the 74 issue bodies and 234 issue comments)
> retain a publicly readable edit history; the 498 deleted PR bot comments are gone.

## Notification posture — unchanged

- **Art. 33(1)** — no duty. Reachability without evidence of use is not an Art. 4(12) breach
  (the 7797 standing rule). The two values still usable do not change this: a usable value is
  reachability, not use.
- **Art. 33(2), Art. 34** — not engaged on these facts.
- **Art. 33(5)** — owed and discharged by the 2026-10-29 determination, this record, and the
  register row and its 2026-11-08 annotations.
- **Data Protection Disclosure §7.2 and the alpha annex §8.1** — not engaged unless and until
  a personal-data breach is signed.
- The §If the finding flips re-opener of the 2026-10-29 determination is unchanged: evidence
  of use starts a **FRESH 72h** clock from awareness of that evidence, Art. 33(2) is assessed,
  Art. 34 is re-run not inherited, and external counsel re-review is triggered.

## Next trigger and closing condition

- **Re-assessment:** the CLO re-assesses again on **2026-11-15** if rotation is still not
  recorded complete in #11294. "Complete" for this purpose means: the
  `egress_audit_ingest_token` clear leg has retired the previous value; `github_webhook_secret`
  is rotated and its post-rotation owner step done or explicitly deferred by decision; and the
  owner has decided the `tunnel_secret` window (rotate or accept the weak ground).

> **Superseded 2026-11-08 (#11711):** the "complete" definition above — its first two
> clauses are now satisfied (the `egress_audit_ingest_token` clear leg verified the
> previous value absent 2026-11-08T07:24Z; `github_webhook_secret` rotated and its
> post-rotation owner step done under the delegation ruling 2026-11-08T07:34Z). Only the
> `tunnel_secret` owner decision remains.

- **Immediate re-opener (unchanged):** evidence of use of an exposed key by a party outside
  its holders starts a fresh 72h clock **at once**, on any date.
- **Closing condition:** when every exposed value is retired, rotated-and-cleared, or ruled
  dead by the owner, the CLO records a closing record; the PROVISIONAL posture and the
  inconclusive limbs E2/E3 are closed by decision at that point, never certified clean
  (E3 has no instrument and is inconclusive by nature).

## Amendment convention

This record is **append-only** after merge. A limb result, a changed disposition, a notice
decision or a correction is added as a dated addendum below, citing the text it annotates; a
superseded sentence gets a `> **Superseded <date> (#N): …**` marker beneath it. Code and
records are cited by function, constant, section or anchor name, never by line number.

## Addendum — 2026-11-08 (rotation completed during the assessment window)

Two completion receipts posted on #11711 during this record's own assessment window — after its #11711 read closed at 07:09Z and before this record committed (~08:00Z) — supersede the rotation-state claims below. The determination and notification posture are unchanged; this addendum corrects state only.

- **2026-11-08T07:24Z (#11711; run `42457579433`):** `egress_audit_ingest_token` rotation COMPLETE — new token live in CURRENT and containers, PREVIOUS verified absent by direct Doppler read. The run's own readback raced Doppler propagation and reported a false failure (the run concluded `failure` at 07:22Z; the rotation itself succeeded). Three real defects fixed en route: #12257, #12304, #12353.
- **2026-11-08T07:34Z (#11711; run `42458754890`):** `github_webhook_secret` rotation COMPLETE — apply+redeploy green (`verdict=owner_step_pending` by design), App webhook secret patched agent-side under the operator's App-key delegation ruling, 26 gap-window deliveries redelivered, post-patch deliveries 200; #12389 closed. The receipt records: "All exposed keys in scope are now rotated — remaining: `random_id.tunnel_secret` (web-2 rebuild) and the dedicated inngest-host pair (own ruling)."

Corrected tally at commit: **9 of the 12 exposed values rotated complete, 2 retired as dead values (the prd signing/event pair, #11293), 1 — `tunnel_secret` — awaiting the owner's roll-forward decision; no printed value remains usable.**

**2026-11-15 re-assessment:** STANDS, narrowed — rotation is still not recorded complete in #11294 because the `tunnel_secret` decision is outstanding. If the owner rules before 2026-11-15, the closing condition governs and the CLO records the closing record on the decision date; the 11-15 re-assessment then does not run.

## Related

- Incident: #11294. Rotation tracker: #11711. Parent: #10205. Determination:
  `knowledge-base/legal/audits/2026-10-29-clo-determination-11294-random-id-log-exposure-art-4-12.md`.
  Evidence record: `knowledge-base/legal/audits/2026-10-31-11294-run-log-evidence-preservation.md`.
  Register index: `knowledge-base/legal/breach-register.md` (2026-10-29 row; 2026-11-08
  annotations).
