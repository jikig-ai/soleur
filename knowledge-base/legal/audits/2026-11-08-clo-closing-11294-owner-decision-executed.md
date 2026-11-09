---
title: "CLO closing record — #11294 owner decision executed (roll-forward); determination stands, CLOSED by decision"
type: clo-attestation
date: 2026-11-08
issue: 11294
related_issues: "10205, 10835, 11293, 11711, 11928, 12299, 12389, 12431"
attestation-authority: clo
status: "DRAFT v1 — internal CLO attestation (Soleur-as-tenant-zero v1), NOT external counsel advice. SIGNED-OFF by the CLO agent on 2026-11-08; operator retains an optional veto."
disposition: "CLOSING RECORD at the 2026-11-08 owner decision: the 2026-10-29 determination STANDS UNCHANGED — a security incident, not a presumed notifiable personal-data breach; the Art. 4(12) second limb remains not established and Art. 33/34 remain not engaged. The owner ruled roll-forward on `tunnel_secret` on 2026-11-08 and the roll-forward executed the same day; every exposed value is now rotated, retired as dead, or rolled forward — no usable printed value remains. The closing condition of the 2026-11-08 re-assessment is satisfied; the PROVISIONAL posture and the inconclusive limbs E2/E3 are closed by decision, never certified clean. #11294 is closed by this record; the 2026-11-15 re-assessment is cancelled as moot."
disposition_history: "2026-10-29 SIGNED-OFF PROVISIONAL on open evidentiary limbs E1–E4; 2026-11-01 CLO position in the evidence record — the cleanup residual does not change the determination, re-assessment trigger set for 2026-11-08; 2026-11-08 re-assessment at the fired trigger — determination stands, re-assessment re-armed for 2026-11-15; 2026-11-08 addendum — rotation completed during the assessment window (9 of 12 complete, no printed value usable); 2026-11-08 CLOSING — the owner ruled roll-forward and execution completed the same day; the matter is closed by decision."
signed_off_at: 2026-11-08
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; operator retains an optional veto)"
awareness_anchor: "2026-10-27T09:31:36Z — issue #11294 filed (unchanged from the 2026-10-29 determination)."
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "not due — unchanged. No evidence of use of an exposed key by a party outside its holders was found through closing, so no 72h clock ever started. The re-opener survives closing: a FRESH 72h runs from awareness of any such evidence."
open_limbs: "none on the determination — E1 run to its coverage limits; E2/E3 closed by decision INCONCLUSIVE (E3 inconclusive by nature); E4 contained, not erased. Residual open limbs carried forward (operational, not evidentiary): 4 comments on #10835 still carrying raw `random_id` values per the tracker rescan (#11711); dead-value state-removal close-out at #11293; E2 signature-failure instrumentation at #11928; web-2 SSH host-key re-capture at PR #12431."
tier_classification: "Tier 1 — an internal determination record. No public document is edited, no right is narrowed, no processing is added. The mirror/SHA/heading gates are NOT engaged. No signed record is edited."
semver: "No TC_VERSION bump."
related_records: "`knowledge-base/legal/audits/2026-10-29-clo-determination-11294-random-id-log-exposure-art-4-12.md` (the determination this record closes); `knowledge-base/legal/audits/2026-11-08-clo-reassessment-11294-rotation-incomplete.md` (the re-assessment whose closing condition this record discharges); `knowledge-base/legal/audits/2026-10-31-11294-run-log-evidence-preservation.md` (the evidence record whose §CLO position armed the fired trigger); `knowledge-base/legal/audits/2026-11-02-a6-no-known-access-record-inngest-keys.md` (the dedicated-pair use-signal measurement)."
---

# CLO closing record — #11294 closed by the executed owner decision, 2026-11-08

> **DRAFT v1. Internal CLO attestation, not external counsel advice.** It records the CLO
> agent's position on 2026-11-08 for the Art. 33(5) file. External counsel re-review is
> reserved for the triggers named in §If the finding flips of the 2026-10-29 determination,
> which are unchanged. It is append-only after merge (§Amendment convention).

## Verdict — the matter is CLOSED. The 2026-10-29 determination stands unchanged

The owner ruled roll-forward on `random_id.tunnel_secret` on 2026-11-08 (in-session go) and the
roll-forward executed the same day, completing ~19:15Z. With that, the closing condition of
the 2026-11-08 re-assessment is satisfied: every exposed value is rotated, retired as dead, or
rolled forward by owner decision. **#11294 is closed by this record.** The determination is
unchanged — a security incident, not a presumed notifiable personal-data breach; the second
limb of Art. 4(12) remains not established; Art. 33 and Art. 34 remain not engaged. The
PROVISIONAL posture and the inconclusive limbs E2/E3 are closed by decision, never certified
clean (E3 has no instrument and is inconclusive by nature). The armed 2026-11-15 re-assessment
is cancelled as moot — its precondition, rotation not recorded complete in #11294, is gone.

## The closing event — roll-forward of `random_id.tunnel_secret`, decided and executed 2026-11-08

- **Owner decision:** roll-forward ruled 2026-11-08 in-session — the `tunnel_secret` window the
  re-assessment left to the owner. Decision date and execution date are the same.
- **Execution (local scoped `terraform -replace` apply):** `random_id.tunnel_secret` was
  replaced; new Cloudflare tunnel `fc4509ed-91fd-4b9a-b613-6de8e649b8d7` created with fresh
  random_id bytes; old tunnel `30f9d116-00e6-43ce-9772-9d0c1262e66a` destroyed. Terraform
  state serial 2606.
- **Ingress and DNS:** the ingress config was rewritten on the new tunnel and the
  `cloudflare_record.deploy`, `cloudflare_record.ssh` and `cloudflare_record.registry` CNAMEs
  repointed to the new tunnel id.
- **web-2 rebuild** — the mechanism that picks up the new connector token, because `user_data`
  is `ignore_changes` and only a rebuilt host takes it: `apply-web-platform-infra.yml` with
  `-f apply_target=web-host-replace -f web_host_key=web-2 -f confirm=REPLACE-web-2`, run
  `42513176800`. The replace gate was clean (`requested=web-2 replaced=1`, all backstop
  counters 0); the boot trail reached `cloud_init_complete` 2026-11-08T19:12:59Z.
- **Post-verify (CF API):** tunnel `soleur-web-platform` status `healthy`, 4 connector
  connections; `deploy.`/`ssh.`/`registry.` answer at the CF Access edge (403 unauthenticated,
  by design); `app.` A-record traffic untouched throughout.
- **Receipts:** <https://github.com/jikig-ai/soleur/issues/11711#issuecomment-6725889615> and
  <https://github.com/jikig-ai/soleur/issues/11294#issuecomment-6725891783>.
- **Follow-on:** the web-2 SSH host key was re-captured; PR #12431 (queued).

## Final exposure tally

Per the tracker receipt: **9 of the 12 exposed values rotated complete, 2 retired as dead
values (the prd signing/event pair, #11293), and `tunnel_secret` rotated via roll-forward. No
usable printed value remains.** The rotation trackers #12299 and #12389 are already closed.

## Closing condition — satisfied; the 2026-11-15 re-assessment is cancelled as moot

The re-assessment's "complete" definition had three clauses, all now satisfied: the
`egress_audit_ingest_token` clear leg retired the previous value (verified absent
2026-11-08T07:24Z, run `42457579433`); `github_webhook_secret` rotated and its post-rotation
owner step done under the delegation ruling (2026-11-08T07:34Z, run `42458754890`); and the
owner decided the `tunnel_secret` window (roll-forward, ruled and executed 2026-11-08). The
re-assessment's own clause governs: *"If the owner rules before 2026-11-15, the closing
condition governs and the CLO records the closing record on the decision date; the 11-15
re-assessment then does not run."* **The 2026-11-15 re-assessment is cancelled as moot.**

## Notification posture — unchanged through closing

- **Art. 33(1)** — no duty arose and none arises now. No evidence of use of any exposed key by
  a party outside its holders was found through closing; reachability without evidence of use
  is not an Art. 4(12) breach (the 7797 standing rule).
- **Art. 33(2), Art. 34** — not engaged on these facts.
- **Art. 33(5)** — owed and discharged by the 2026-10-29 determination, the 2026-11-08
  re-assessment, this closing record, and the register row and its annotations.
- **Data Protection Disclosure §7.2 and the alpha annex §8.1** — not engaged; no personal-data
  breach was signed.
- **Re-opener survives closing (unchanged):** evidence of use of an exposed key by a party
  outside its holders starts a **FRESH 72h** clock from awareness of that evidence, on any
  date; Art. 33(2) is assessed, Art. 34 is re-run not inherited, and external counsel
  re-review is triggered.

## Residual open limbs carried forward

Operational limbs only — none is an evidentiary limb of the determination and none blocks this
closing; each is carried on its own issue:

- **#10835 rescan (E4-class containment residual):** the redaction rescan flagged in the
  tracker found **4 comments on #10835 still carrying raw `random_id` values**; their redaction
  is an operational follow-through tracked at #11711. The standing E4 residual — the edit
  history of the redacted items stays publicly readable — is unchanged by design.
- **#11293 — dead-value close-out:** the prd signing/event pair is retired as dead values;
  close-out is state removal tracked at #11293.
- **#11928 — E2 instrumentation:** the signature-failure alert rules that would make
  use-signal limbs continuously instrumented remain open; E2 itself is closed by decision
  INCONCLUSIVE, never certified clean.
- **PR #12431 — web-2 SSH host-key re-capture (queued):** post-rebuild evidence capture, not an
  exposure limb.

## Limb states at closing

| Limb | 2026-11-08 re-assessment state | State at closing |
|---|---|---|
| E1 — run-log census | Run to its coverage limits | Unchanged — run to its coverage limits; the horizon, NOLOG, artifact and earlier-attempt residuals stand |
| E2 — use-of-key signals | Partly run, INCONCLUSIVE | **Closed by decision INCONCLUSIVE** — never certified clean; instrumentation continues at #11928 |
| E3 — who viewed the logs | INCONCLUSIVE BY NATURE | **Closed by decision** — inconclusive by nature; no instrument exists |
| E4 — copies outside the run logs | Contained, not erased | **Contained, not erased** — the #10835 rescan residual is carried open above |
| Rotation/remediation | 9 of 12 complete, `tunnel_secret` awaiting the owner | **Complete by the owner's roll-forward decision, executed 2026-11-08** — no usable printed value remains |

## Amendment convention

This record is **append-only** after merge. A limb result, a changed disposition, a notice
decision or a correction is added as a dated addendum below, citing the text it annotates; a
superseded sentence gets a `> **Superseded <date> (#N): …**` marker beneath it. Code and
records are cited by function, constant, section or anchor name, never by line number.

## Related

- Incident: #11294. Rotation tracker: #11711. Parent: #10205. Determination:
  `knowledge-base/legal/audits/2026-10-29-clo-determination-11294-random-id-log-exposure-art-4-12.md`.
  Re-assessment: `knowledge-base/legal/audits/2026-11-08-clo-reassessment-11294-rotation-incomplete.md`.
  Evidence record: `knowledge-base/legal/audits/2026-10-31-11294-run-log-evidence-preservation.md`.
  Register index: `knowledge-base/legal/breach-register.md` (2026-10-29 row; 2026-11-08
  closing annotation).
