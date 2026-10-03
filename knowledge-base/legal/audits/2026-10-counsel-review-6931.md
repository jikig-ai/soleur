---
title: "Counsel review audit — #6931 / PR #9352 (guest-side fresh-boot LUKS for web hosts, ADR-263: Article 30 register + compliance-posture annotations)"
type: counsel-review
date: 2026-10-01
issue: 6931
pr: 9352
status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)
signed_off_at: 2026-10-01
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; the operator retains an optional veto)"
disposition: "DISCHARGED. Two register artifacts in scope (article-30-register.md, compliance-posture.md; 6 + 10 changed lines). Every web-2 at-rest sentence is conditioned on the live conversion (#9372) or states plaintext-but-empty. Four precision edits were applied in-cell by this review (E1-E4, below); no blocking finding."
blocking_findings: []
applied_in_review:
  - "E1/E2 — Residual R4 reader set: added 'and by holders of the Terraform state (R2 backend), whose user_data attribute carries it (no new reader class: the full-prd doppler_token already sits in the same user_data map)' to the Hetzner DPA-scope row (compliance-posture.md) and the cross-host replication row (article-30-register.md)."
  - "E3/E4 — Escrow wording: 'goes to the escrow bucket' replaced by 'is copied, best-effort at birth (a failed copy is non-fatal and leaves escrow=missing), to the escrow bucket already recorded ... as an open classification question (#7671)' in the PA-1 recipients (e) cell of article-30-register.md and the T-1 row of compliance-posture.md."
optional_precision_notes:
  - "O1 — The marker write token (doppler_service_token.workspaces_luks_marker_write, mirrored into repo-level Actions secret DOPPLER_TOKEN_WORKSPACES_LUKS_MARKER) is read/write on a branch config that inherits prd, so it also resolves ~116 prd secrets and sits with every workflow on main. The Terraform comment and ADR-263 D5 state this truthfully; the registers do not repeat it. Marginal over the existing DOPPLER_TOKEN_WRITE repo secret, so not conditioned. If a future register pass records CI credential custody, list it there."
  - "O2 — The encryption-posture ledger row for hcloud_volume.workspaces stays plaintext-exception with expires_on 2026-10-22 (tracking #6897). #9372 (or an exception renewal) must land before that date or the ledger gate fails; this is an engineering dependency, not a register defect."
  - "O3 — Retention of the web-2 header escrow object after a volume rebirth (the old LUKS UUID's object remains in the bucket) is not stated. A LUKS header is not shown to be personal data (open at #7671); fold the answer into #7671's resolution."
  - "O4 — #9377 (split the web-host escrow credential from web-1's backup-bucket access; bucket versioning/object lock) remains the open hardening item for the integrity exposure of web-1's recovery path. Correctly disclosed as accepted for the standby phase."
attests:
  - "knowledge-base/legal/article-30-register.md — PA-1 (d) recipients and (e) third-country-transfer dated entries, and the cross-host-replication DRAFTED/NOT-YET-ACTIVE row's dated entry incl. Residual R4, as amended by E2/E3"
  - "knowledge-base/legal/compliance-posture.md — Hetzner DPA-scope row dated entry incl. Residual R4, TS-1 / T-1 (both pairs of rows) dated annotations, as amended by E1/E4"
does_not_attest:
  - "The engineering change itself — workspaces-luks-provision.sh correctness, the Terraform wiring, the verify workflow, the sentry alert contracts, the runbooks and tests (technical controls; counsel reviewed only what the registers say about them)."
  - "The live conversion (#9372). Nothing here attests that web-2 is, or will be, LUKS-backed; the registers deliberately do not either."
  - "docs/legal/* and the Eleventy mirrors — untouched by this PR; their 'Encrypted workspace storage' wording is scoped to the volume workspace git data is served from (web-1) and remains true."
art_33_triggered: false
art_34_triggered: false
re_evaluation_triggers: "(1) The live conversion (#9372) running: re-read every 'IF AND WHEN' limb against the actual probe row and flip the ledger row; the 'plaintext-but-empty' sentences must then be superseded, not deleted (append a Superseded marker). (2) web-2 receiving serving weight or any workspace data before #9372: the register's 'holds no personal data' premise fails and this attestation lapses. (3) Any publication of an at-rest claim naming web-2. (4) #7671 resolving that a LUKS header is personal data. (5) First arms-length user, EEA-out, or a regulated-industry customer (external counsel re-review)."
---

# Counsel review audit — #6931 / PR #9352 (fresh-boot LUKS, ADR-263)

Evidence for the ship Phase 5.5 Counsel-Review CLO-Attestation Gate on PR #9352 (issue #6931). The gate
fired on the `knowledge-base/legal/` edits this PR carries. Brand-survival threshold: `single-user
incident`. The CLO agent is the v1 attestation authority; the operator holds an optional veto.

## Question put

Does any sentence assert, or let a reader infer, that web-2 data is encrypted at rest before #9372
lands, or misstate what the implementation does (lawful basis, retention, who can read the escrow
credential, residual risk)? Does any personal data move, or any processor arrive?

## Method

Read the full diff (`git diff origin/main...HEAD` on the two registers), ADR-263, the ledger row for
`hcloud_volume.workspaces` (`scripts/encryption-posture-ledger.json`), and checked each implementation
claim against `workspaces-luks-provision.sh` (`_escrow`), `workspaces-luks-fresh-boot.tf`,
`lb-weight-gate.sh` and `cloud-init.yml`. Cited by function and resource name, not line number.

## Per-artifact verdicts

| Artifact / cell | Verdict | Basis |
|---|---|---|
| article-30-register.md, PA-1 (d) recipients, web-2 entry | CLEAN | "holds no personal data", "serving weight 0, never pooled", "gains no new recipient, sub-processor or location" match ADR-263 and the gate. The marker is described as shape-only, which is what `lb-weight-gate.sh` does (ISO-8601 shape and age, not provenance). No encryption claim. |
| article-30-register.md, PA-1 (e) transfers entry | CLEAN after E3 | Every at-rest sentence is an "IF AND WHEN ... and not before: until then it is plaintext-but-empty and no register entry may describe it as encrypted" conditional. "No Art. 32 at-rest exposure arises while it holds none" is true because the volume is empty and held at weight 0. Escrow wording tightened to match `_escrow` (best-effort, non-fatal, `escrow=missing`). |
| article-30-register.md, cross-host replication row | CLEAN after E2 | The old sentence "web-2's `for_each` volume is plaintext today per ADR-143 R3" is kept and conditioned, not silently overwritten. R4 (token in user_data, ~116 prd secrets, shared `WORKSPACES_LUKS_KEY`, escrow-credential overwrite/delete risk to web-1's header backup, #9377) matches ADR-263 D4 and "Shared-passphrase residual" and the `workspaces_luks_fresh_boot` token comment. Reader set completed (Terraform state). The row stays DRAFTED / not-yet-active. |
| compliance-posture.md, Hetzner DPA-scope row | CLEAN after E1 | "No DPA, sub-processor, location or transfer change" is correct: same Hetzner account and `hel1`. R4 text identical to the Art. 30 copy. |
| compliance-posture.md, TS-1 (both rows) | CLEAN | "Precondition of the GA flip, not a statement about web-2 today" and "conditional on the live conversion" correctly refuse an at-rest claim. R4 "applies from that conversion" is accurate (the token is in user_data of a host born on the new path). |
| compliance-posture.md, T-1 (both rows) | CLEAN after E4 | EU pin unchanged; no new host, location or recipient. Escrow wording aligned with E3. |

## Findings on the question put

1. **No encrypted-before-#9372 assertion or inference.** Every web-2 at-rest sentence in the diff is
   either "plaintext-but-empty" or an "IF AND WHEN ... rebuilt ... and the daily probe has read
   `crypto_LUKS` ... and not before" conditional. The ledger row agrees: still `plaintext-exception`,
   and its evidence string says "Until then the row is truthfully a plaintext exception". The published
   privacy policy line "Encrypted workspace storage" is scoped to the volume workspace git data is
   served from; web-2 serves nothing, so no published claim is falsified or newly implied.
2. **Lawful basis and retention.** Not touched by the diff, correctly: no new processing activity, no
   new category, no new purpose. Art. 6(1)(b) and the PA-1/PA-2 retention cells stand unchanged.
3. **Who can read the escrow credential.** The diff said the fresh-host token "reaches ... the
   header-escrow credentials" and is readable by root-equivalent host users. The only host users are
   `root` and `deploy` (docker group, root-equivalent by design in `cloud-init.yml`), so that is
   accurate for the host. It omitted the Terraform state, which carries `user_data` and so the token;
   the plan's own threat list names state as a channel. Added by E1/E2. No new reader class exists
   because the full-`prd` `doppler_token` is already in the same `user_data` map.
4. **Residual risk.** R4, the shared passphrase and the escrow integrity exposure are disclosed with
   their mitigations stated as bounded ("a default-drop on `docker0` only, installed only once allowlist
   resolution succeeds ... an allowlist data test, no more"). That matches ADR-263 D4 and does not
   oversell the egress firewall.
5. **No personal data moves; no new processor.** The mechanism moves a LUKS header (key-slot metadata,
   not content) to the existing Cloudflare R2 escrow bucket, a passphrase fetch from Doppler, and
   host-tagged probe rows to Better Stack, all existing processors and vendors. The write-token path is
   GitHub Actions to Doppler, also existing. Header-as-personal-data classification remains the open
   #7671 question, now recorded as such in the new wording rather than described as settled.

## Disposition

**DISCHARGED.** No blocking finding. E1-E4 are in-cell corrections applied by this review; the
precision notes O1-O4 are non-conditioning. The attestation covers the register prose only and lapses on
re-evaluation trigger (2) if web-2 receives weight or data before #9372.

## Addendum — 2026-10-03 (#9377)

Supersession pointer only; the body above is the dated record and is not edited. This addendum is not a re-attestation.

> **Superseded 2026-10-03 (#9377):** the statements above that describe the shared `WORKSPACES_LUKS_KEY` as a present
> residual (per-artifact rows for the cross-host replication cell and the Hetzner DPA-scope cell, and "Residual risk"
> item 4) are superseded for every NEW web-class birth by the #9377 passphrase split: a web-class host born after it reads a
> passphrase generated independently of web-1's. The register cells carry the replacement wording, scoped to new births and
> stated as narrowed, not eliminated: the pre-split fresh-boot token still resolves web-1's passphrase and pair until it is
> retired. The same change moves `escrow=missing` on a web-class birth from a quiet issue stream to a page (an alerting change,
> not a processing change). Every web-2 statement stays conditioned on the live conversion (#9372); nothing here says web-2
> is encrypted. Re-attestation is owed at #9372 and before web-2's serving weight rises, and a passphrase-loss recovery path
> is to be recorded when data lands (Art. 32(1)(c)).
