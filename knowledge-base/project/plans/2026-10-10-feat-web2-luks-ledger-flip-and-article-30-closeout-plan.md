---
title: "feat: flip the web-2 workspaces ledger row to luks and supersede the conditioned Article 30 / compliance-posture sentences (#9372 closeout, PR 1)"
date: 2026-10-10
slug: web2-luks-ledger-flip-and-article-30-closeout
branch: feat-one-shot-9372-web2-luks-ledger-closeout
issue: 9372
type: feat
priority: p2-medium
domain: engineering, legal
brand_survival_threshold: aggregate pattern
lane: cross-domain
---

## Overview

#9372 asked for web-2 to be converted to a LUKS volume and for the record to say so. The conversion happened (rebirth
runs of 2026-10-06, host replace of 2026-10-07) and the #6931 grader passed on 2026-10-10 (sweeper run 38083925201,
which auto-closed #6931). What is left is the record: the encryption-posture ledger row for `hcloud_volume.workspaces`
still reads `plaintext-exception`, and the Article 30 register and compliance-posture record still carry sentences that
are conditioned on this event.

This plan is **PR 1** (this branch, draft PR #9941): the ledger flip, the linter changes the flip needs, the legal
supersession markers, and the tracking of the open acceptance items. **PR 2** (retire the two single-use workflows) is
described under "Follow-up: PR 2" and is not part of this PR's tasks. `Closes #9372` goes on PR 2 (the final PR), not
here and not in any title.

What the record may say is bounded by the graded rows, and by the ADR-263 addendum of 2026-10-08: the evidence is
"the running instance's readiness row says it formatted or opened the volume, plus green probe rows on three distinct
days". It is **not** evidence that the volume reopens after a reboot, it says nothing about web-2 holding data (it holds
none), and it must not be worded "at boot", "survives a reboot" or "reborn".

## Premise Validation (Phase 0.6)

Every claim in the brief was checked against live state on 2026-10-10. Read-only evidence only: Better Stack through
`scripts/betterstack-query.sh`, the Hetzner API with the read-only token, `gh`, and the repository. No dispatch, no
apply, no Doppler write.

| Brief claim | Verified state | Consequence |
|---|---|---|
| #6931 auto-closed by sweeper run 38083925201, PASS, 3 distinct GREEN days, boot dd08ac9d | Held. Run 38083925201 concluded success; #6931 CLOSED 2026-10-10T20:31:49Z. Re-ran `scripts/followthroughs/web2-luks-live-6931.sh` read-only: PASS, 3 distinct days, newest probe row 20.3 h old, boot dd08ac9d | Evidence base is real; Phase 0 re-runs it at implementation time and at merge time |
| "Hard deadline: the posture exception expires 2026-10-22" | **Stale for this row.** The ledger row's `exception.expires_on` is **2026-12-29** (re-scoped by PR #9348, merged 2026-10-08; #6931 comment 2026-10-08). The rows that expire 2026-10-22 are other stores (`hcloud_volume.git_data`, `redis.session_store`, `git_data.baked_credentials_on_host`, three zot/inngest links; tracking #6897) | No deadline pressure from this row; no extension is needed; other rows are out of scope (do not touch #6897 rows) |
| "the ledger needs a per-host row split" | **Dissolved.** `hcloud_volume.workspaces` is `for_each = local.plaintext_workspaces_hosts` = every web host except web-1, i.e. web-2 only; web-1's volume is the separate row `hcloud_volume.workspaces_luks`; web-1's plaintext instance was wiped, deleted and forgotten (#6604 step 7, runs 37801674740 / 37803274724) | No split. Replaced by a mechanical per-instance declaration (`multiplicity`) so a future web host cannot inherit the claim silently |
| "the linter fails a luks row for that resource" | Confirmed on a scratch copy (flipped ledger fails: attachment does not bind volume). A prototype with the binding regex relaxed and the same-file pair check removed then PASSES, **because the mapper `workspaces` resolves through web-1's apparatus** (`workspaces-cutover.sh`), not web-2's provisioner (`workspaces-luks-provision.sh`, unquoted `MAPPER_NAME=workspaces`, which `resolve_mapper_operand` cannot resolve) | Two more linter gaps beyond the two in #9572: the mapper join is a name-similarity join (the class ADR-140 rejects), and the pinned provisioner carries no mount evidence the scanner can read (`FSTAB_LINE='/dev/mapper/workspaces ...'` has no lowercase `fstab`, `MAPPER="/dev/mapper/$MAPPER_NAME"` has a `$`, no `MOUNT=` line; the prototype passed only through web-1's bootstrap gate). Fixing only the two listed gaps would flip a row the linter cannot actually prove |
| "flip ... `live_coverage_floor` 2->3" | Available rows today: `hcloud_volume.registry`, `hcloud_volume.workspaces_luks` (2). Adding web-2 makes 3 | Floor 2 -> 3 in the same commit as the row |
| Ledger row text (volume 106466179, "created ext4", web-1 backstop narrative, "#9372 dispatch pending") | **Stale.** Hetzner API read 2026-10-10: `soleur-web-platform-data-web-2` is id **107059048**, created 2026-10-06T18:21:50Z, `format: null` (raw), attached to server 169271252; the old id 106466179 answers 404. Rebirth workflow runs 37508066236, 37508997529, 37516716515 succeeded on 2026-10-06 (two earlier runs failed) | Row text is rewritten from measured facts, not edited around |
| Readiness evidence | Better Stack `SOLEUR_FRESH_BOOT_READY` for `soleur-web-2`: 2026-10-06T18:24Z `luks_arm=formatted escrow=ok` boot 77985247; 2026-10-06T19:36Z `luks_arm=opened escrow=ok` boot 479cd3f3; 2026-10-07T20:07Z `luks_arm=opened escrow=ok` boot dd08ac9d (current). Probe rows: `crypto_LUKS`, `/dev/mapper/workspaces`, `escrow=ok header=readable`, daily | Only the newest row is "the running instance"; ADR-263 records instance identity as a weak anchor, so no claim is made about the two earlier boots |
| Escrow-create retirement checklist done | Held. `apply-web-escrow-create.yml`, its test and names helper are absent; no rows in the suite manifests, `PROMOTED_FILES`, `run-registered-suites.sh`; no "Step 0a" subsections remain; the only remaining mentions are `scripts/web2-rebirth.sh` `flip-precondition` (asserts the file stays absent) and a past-tense `model.c4` sentence | Nothing to do for PR 2 on this list, except re-deriving the census count (below) |
| Item 3, escrow preflight ordering | Held. `.github/workflows/web2-luks-rebirth.yml` step "Escrow readiness preflight" runs before `Terraform init` and before any Hetzner call; its text is pinned by `plugins/soleur/test/web-host-escrow-preflight-census.test.ts` | Recorded as verified on #9372 and in the audit; no code |
| Item 3, passphrase-loss recovery; escrow=missing re-escrow | Neither exists (runbook: "There is no escrow retry"; ADR-006 caveat: no verified recovery). No tracking issue existed | Filed **#9948** and **#9949** (milestone Phase 4: Validate + Scale) |
| Item 4, #9642 owner-gated | OPEN. Its trigger has partly passed: the real (non plan-only) rebirth dispatches ran on 2026-10-06 under the unchanged 1 GiB / 64 MiB thresholds. The deletion happened; the decision is now about what the owner accepts retrospectively, and PR 2 deletes the constants it concerns | Surface to the owner in the PR body and the session summary; **not decided here** |
| "#9750 (replace-not-reboot for other users) is separate" | #9750 is CLOSED | Out of scope either way |
| Sibling drafts | #9925 edits `hcloud_volume.inngest_redis_luks` row, Article 30 PA-13, one compliance-posture row, ADR-263 tail. #9051 and #9529 add lines to `article-30-register.md` away from lines 62/85. #8626 is CONFLICTING since 2026-09-28 and rewrites the linter and schema (`multiplicity`, `records`) | See "Sibling PR overlap and rebase plan" |

## Research Reconciliation: Spec vs. Codebase

| Spec / brief says | Codebase reality | Plan response |
|---|---|---|
| Runbook closing row 2: split the row, accept `[each.key]` bindings and a sibling-file pair | Split dissolved; `[each.key]` and sibling pair confirmed; mapper join is an additional gap | Linter work is four changes plus a `multiplicity` declaration, not two (binding, key chain, apparatus pin with its resolver and mount-evidence arms) |
| Runbook row 5 / 10-04 comment: "census count back to 3" | `MAIN_ROOT_TF_WORKFLOWS` in `plugins/soleur/test/terraform-target-parity.test.ts` lists five files today (four apply/drift/validation workflows plus `web2-luks-rebirth.yml`) | PR 2 re-derives the number by running the census, not from the runbook arithmetic |
| ADR-263 addendum: "Nothing in this addendum is evidence for the encryption-posture ledger, Article 30 or any customer-facing sentence" | That sentence was written before the grader passed; it is now satisfied for the ledger and Article 30 (not for any customer-facing sentence) | Append-only ADR addendum records the grade and the flip; nothing is rewritten |
| #9572: "linter change is a separate reviewed change" and "flip in the same change as the two linter fixes" | The two bullets point opposite ways | Resolved as one PR, two ordered commits (linter first, reviewed as a security-linter change); split trigger below |

## Research Insights

### Property List (Phase 0.6b)

1. The ledger says `luks` for web-2's volume only because the linter resolved the apparatus for that volume mechanically, not by name similarity.
2. A plaintext row can still not cite a sibling volume's LUKS apparatus (the #6588 false-PASS class; fixture TS-15 stays green and unchanged).
3. The claim cannot outrun its detector: a standing, alerting probe exists for web-2 specifically.
4. Article 30 and compliance-posture say no more than the graded rows show; superseded text stays as the dated record; the three cells carrying the same conditional span stay byte-equal.
5. `live_coverage_floor` reflects the new count so losing web-2's coverage is caught.
6. Each open acceptance item is closed or tracked, with a milestone; none is implicit.
7. The owner decision #9642 is surfaced, not decided.

### Cut List (Phase 0.6b)

| Mechanism | Property it would buy | Disposition |
|---|---|---|
| Per-host row split | 1 | Cut: the row is web-2-only already; replaced by `multiplicity` (property 1, future-host safety) |
| Extending the 2026-10-22 exception | none for this row | Cut: this row's exception expires 2026-12-29 and the flip removes it |
| Moving the passphrase pair or the attachment between `.tf` files so the existing same-file check passes | 1 | Cut: satisfies the linter by file layout, not by proof; touches `-target` surfaces and tests that pin file anchors |
| A new ADR for the key-chain check | 1 | Cut: ADR-140 owns the Layer A contract; a dated addendum there is the home (avoids a contested ordinal; siblings are claiming 282+) |
| A web-2 "daily five-step probe" claim | 3 | Cut: the web-1 verify job reads web-1 over SSH; web-2's detector is the `web2_marker` job plus luks-monitor rows, and the row says so in those words |
| Editing `model.c4` in PR 1 | none | Cut: PR 1 changes no C4 element or edge; the stale rebirth sentence is PR 2's (one regeneration of `model.likec4.json`) |

### Value-proposition measurement (Phase 0.6c)

Not applicable: no cost or performance saving is claimed.

### Evidence pulled (no SSH, no dashboard)

- Grader: `doppler run -p soleur -c prd_terraform -- bash scripts/followthroughs/web2-luks-live-6931.sh` (with `SOLEUR_FT_EARLIEST=2026-10-10T20:10:00Z`) printed PASS, exit 0.
- Rows: `scripts/betterstack-query.sh --since 5d --grep SOLEUR_FRESH_BOOT_READY` and `--since 2d --grep luks-monitor`, decoded with `jq -r '.raw | fromjson'`.
- Hetzner: `GET /v1/volumes?name=soleur-web-platform-data-web-2` and `GET /v1/volumes/106466179` with `HCLOUD_TOKEN_READONLY`.
- Linter prototype: a scratch copy of the linter and a flipped ledger under the session scratchpad; nothing in the repository was edited.

### Institutional learnings applied

- `2026-09-14-the-sweep-that-retired-false-sentences-wrote-new-ones-from-my-own-issue-comment.md`: before `available`, read the schema's definition and name the standing probe; the new sentences must be re-derived from rows, not from an issue comment.
- `2026-07-16-removing-a-false-claim-can-strengthen-the-false-claim-that-leaned-on-it.md` and `2026-10-06-narrowing-a-guard-leaves-every-sentence-about-its-old-scope.md`: after superseding, re-check sentences that lean on the superseded subject; append dated markers, do not rewrite.
- `2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md` and `2026-07-19-a-self-graded-mutation-battery-went-vacuous-twice-in-one-pr-...md`: each new check needs a negative fixture and an independent mutation row; the battery's positive control must itself be load-bearing.
- `2026-09-27-a-read-only-proof-must-measure-with-the-writers-predicate-not-a-narrower-one.md`: the binding regex must accept exactly what `server.tf` writes, no wider.
- `2026-08-04-the-code-i-read-as-not-encrypted-was-a-default-errno-bucket-...md`: `cryptsetup isLuks` is not a discriminator; the claim rests on `device_type=crypto_LUKS` rows, which is what the probe emits.
- `2026-05-07-pr-title-closes-keyword-ignores-qualifiers-...md`: `Closes #9372` in the body of the final PR only.

## Problem Statement

1. The ledger row `hcloud_volume.workspaces` is a plaintext exception whose text describes a state that no longer exists (volume 106466179, ext4, web-1 backstop, dispatch pending).
2. The linter cannot accept a `luks` row for this resource. Two gaps are in #9572 (indexed binding; sibling-file key pair). Two more were found while planning: the mapper join resolves through web-1's apparatus, and the pinned provisioner has no mount evidence the scanner reads.
3. Three cells state, conditionally, that web-2 is plaintext-but-empty until the conversion has run and the probe has read `crypto_LUKS`: Article 30 PA-1 (e), the Article 30 cross-host replication row (g), and the compliance-posture Hetzner DPA-scope row. Four more sentences in Article 30 / compliance-posture (rows 164, 165, 167 and the "Once converted" clause) and one in the web-1 destruction record are conditioned on the same event.
4. The three open acceptance items from #9372 (2026-10-03 comment) must each be closed or tracked.
5. #9642 is owner-gated and must be put in front of the owner.

## Proposed Solution

### A. Linter and schema (commit 1, no ledger change)

New keys are optional for the rows that exist today (singleton bindings: web-1's `workspaces_luks`, registry, inngest,
git-data), so the real ledger stays green after this commit with the web-2 row still `plaintext-exception`. **They are
mandatory for any row that uses the new indexed arm**: an indexed row missing `apparatus`, `key_chain` or `multiplicity`
FAILs with a message naming the missing key. Without that rule the natural repair for a red lint (delete `apparatus`) would
fall back to the name-join and turn the flipped row green over web-1's apparatus (`#222` class: the most natural repair of a
new refusal must itself be refused). Changes to `scripts/lint-encryption-posture.py`, `scripts/encryption-posture-ledger.schema.json`
and `scripts/lint-encryption-posture.test.sh`. Design from the CTO consult (2026-10-10), kept minimal:

1. **Indexed binding.** `attachment_binds_volume` also accepts `volume_id = <vtype>.<vname>[each.key].id`, but only when
   the attachment block and the volume block each carry exactly one `for_each` and the two expressions are textually identical
   (here `local.plaintext_workspaces_hosts`); a second `for_each` token in either block FAILs. Every other index form
   (`["web-1"]`, `[0]`, `[each.value.x]`) is rejected. The literal-reference regex for singletons is unchanged. MB-L1 wraps
   only the equality condition (deleting the whole arm would fail "does not attach", not pass).
2. **Key chain** (optional `device_binding.key_chain`, mandatory for indexed rows). The linter verifies each hop by literal
   HCL reference: the consumer `hcloud_server.web`'s `user_data` argument map carries exactly
   `workspaces_volume_id = contains(keys(local.plaintext_workspaces_hosts), each.key) ? hcloud_volume.workspaces[each.key].id : "retired-6604"`
   (the ternary the repo writes today, accepted as that shape and no other) AND
   `workspaces_luks_fresh_boot_token = <token>.key`; the token's `config` equals the secret's `config`
   (`doppler_config.workspaces_luks_web.name` on both); the secret's `value` is `<password>.result`. When present it
   **replaces** the same-file pair check for that row and never relaxes it for a row without it. One global guard: no
   `random_password` may be claimed by two luks rows, where a row's implicit claim is every `random_password` declared in its
   attachment's own file (this single guard also covers "web-2's password differs from web-1's", so no separate separation
   guard exists). MB-L5 uses a dedicated two-row fixture (TS-15 fails at the binding check first and cannot exercise it).
3. **Apparatus pin** (optional `device_binding.apparatus`, mandatory for indexed rows). Names the file holding this volume's
   `cryptsetup luksFormat` and `luksOpen`. When present, apparatus and mount evidence are read from that file only, not from
   any file under `apps/*/infra/` that resolves the same name. Two scanner arms, **scoped to pinned files so no existing row's
   verdict can move** (AC: the parity table for the real ledger is byte-identical before and after commit 1): (a)
   `resolve_mapper_operand` accepts an unquoted `VAR=literal` assignment (MB-L6; the provisioner is embedded in cloud-init
   `user_data`, which is why the line is not quoted); (b) mount evidence accepts an fstab-shaped line,
   `/dev/mapper/<name> <mountpoint> <fstype> ...`, inside a variable assignment (`FSTAB_LINE='...'`) of the pinned file (MB-L2).
   Phase 1.0 prototypes both against the real provisioner in scratch before any test is written. The row's mapper becomes
   `workspaces` (today `workspaces-plain`).
4. **Multiplicity** (row-level optional `multiplicity: {instances}`, mandatory for indexed rows; the key name matches #8626's).
   `instances` must equal the key set the volume's `for_each` resolves to. Resolution supports exactly one shape,
   `{ for k, v in var.<map> : k => v [if k != "<key>" ...] }` over the variable's default keys (comments stripped first;
   `variables.tf` carries a long comment block before the default); any other shape fails closed with a message naming what to
   declare. Both directions are checked (a new host key; a declared extra key such as `web-1`). Effect: a new key in
   `var.web_hosts` reds the lint until the row is re-attested.
5. **Mandatory-when-indexed.** An indexed row missing `apparatus`, `key_chain` or `multiplicity` FAILs naming the key.
6. **Validator.** The ledger validator (`_validate_store`, `OPTIONAL_TOP`) is hand-rolled and does not read the JSON schema;
   it gains shape checks for the three new keys so a malformed row FAILs instead of raising a KeyError. The schema file is
   updated in step so the two do not drift.

### B. Ledger row (commit 2)

`hcloud_volume.workspaces`: `mechanism: luks`; `device_binding` with `mapper: workspaces`, `apparatus:
apps/web-platform/infra/workspaces-luks-provision.sh`, `key_chain` (consumer `hcloud_server.web`, token
`doppler_service_token.workspaces_luks_fresh_boot_web`, secret `doppler_secret.workspaces_luks_web_key`, password
`random_password.workspaces_luks_web`), `multiplicity.instances: ["web-2"]`; `live_verification: available`;
`exception` removed; `live_coverage_floor: 3`.

Text, rewritten from measured facts and in these words (CLO guardrails, below):

- `evidence`: content anchors only (no line numbers): the provisioner's `cryptsetup luksFormat` / `luksOpen` pair, the
  `[each.key]` attachment, the web-class key pair. Observed 2026-10-10: volume 107059048, born raw 2026-10-06T18:21Z,
  readiness row of the running instance `luks=1 luks_arm=opened escrow=ok` boot dd08ac9d (2026-10-07T20:07Z), probe rows
  `device_type=crypto_LUKS mount_source=/dev/mapper/workspaces` on three distinct days, grader PASS (sweeper run
  38083925201). State what `available` means here and what it does not: "the probe is host-side luks-monitor rows read
  from Better Stack and judged daily by the `web2_marker` job of `workspaces-luks-verify.yml` (the web-1 SSH probe does not
  cover web-2). It establishes that the volume sits on a LUKS container the instance opened; it does not establish that
  it reopens after a reboot, and web-2 holds no workspace data." Precedent: the `hcloud_volume.registry` row's
  "the two share the word and not the strength" note.
- `does_not_defend`: a leaked credential; any read on the host while the mapper is open; no verified recovery from loss of
  the passphrase (two copies, Doppler and unversioned state; header restore never exercised, #9948); the escrow has no
  re-escrow step (#9949); the volume has no Hetzner delete protection; a future web host key is covered by static
  evidence only until its own probe exists.
- `disclosed_as: not-publicly-claimed` (web-2 serves nothing; "Encrypted workspace storage" in the privacy policy is
  scoped to the volume workspace git data is served from and stays unchanged; asserted, not linted, for luks rows).
- `defends_against`: a seized, RMA'd or snapshot-imaged Hetzner block volume of web-2.
- No `reevaluate_when` field exists on a luks row (it lives in `exception`); the "weight or data" trigger is recorded in the
  audit and in the marker instead (CLO item 4).

### C. Legal records (commit 2)

Append-only dated markers; superseded text stays. CLO-drafted, owner veto. One marker text, pasted into all three cells so
they stay byte-equal after bold removal:

| Cell | Location (anchor) | Action |
|---|---|---|
| Article 30 PA-1 (e) | after "so no Art. 32 at-rest exposure arises while it holds none." (the span "IF AND WHEN web-2 has been rebuilt ... may describe it as encrypted") | marker |
| Article 30 cross-host replication row (g) | after the "[Updated 2026-10-01 (#6931, ADR-263), as to "web-2's `for_each` volume is plaintext today per ADR-143 R3"" clause; the same span | marker |
| compliance-posture, Hetzner DPA-scope row | after "its volume is plaintext-but-empty today." (same span) | marker |
| compliance-posture TS-1 (row "Until the single-use rebirth (#9372) has run and the daily probe has read `crypto_LUKS`") and the "not a statement about web-2 today" clause | | marker |
| compliance-posture T-1 ("Once web-2 has been converted, its LUKS header copy is copied") | | marker |
| Article 30 PA-1 (e) "Once converted, web-2's LUKS header copy is copied, best-effort at birth" | | marker |
| `knowledge-base/legal/audits/workspaces-plaintext-destruction-record.md`, "Other copies of workspace data" ("web-2's plaintext volume (intended empty, ..., contents unprobed, #6931)") | | dated pointer note below the table (a field value is not rewritten) |

Marker text (CLO drafts the final wording; this is the shape the guardrails allow). The four other placements (TS-1, T-1, the PA-1 "Once converted" clause, the destruction-record pointer) carry the same evidence sentence with a cell-specific one-line lead-in naming the superseded sentence by its anchor; "the recovery sentences below" is worded "the recovery sentences in this cell" so the referent is stable:

> **Superseded 2026-10-NN (#9372; fires on the merge of PR #9941):** web-2's `/workspaces` volume (Hetzner id 107059048,
> born raw 2026-10-06) is LUKS-formatted and was opened by the running instance (readiness row `luks=1 luks_arm=opened
> escrow=ok`, boot dd08ac9d, 2026-10-07T20:07Z), and the daily luks-monitor probe rows read `crypto_LUKS` on
> `/dev/mapper/workspaces` on three distinct days (the #6931 grader returned PASS on 2026-10-10). That is
> formatted/opened plus green probes; it is not evidence that the volume reopens after a reboot (ADR-263 addendum
> 2026-10-08). web-2 still holds no personal data and sits at serving weight 0. The recovery sentences in this cell are unchanged
> and stay conditioned on the data-bearing period (#9948, #9949, #7992).

Guardrails (CLO, 2026-10-10): may say formatted/opened, the grader PASS with its date, "immutability" as the rule, "holds no
data"; may not say "at boot", "survives a reboot", "reopens after reboot", "reborn", any encrypted-at-rest claim for data
web-2 does not hold, any claim that escrow restores, or "split per host". Do not change the premise statements ("holds no
personal data", "serving weight 0", the anti-pooling gate), the recovery sentences, the open C1 and C2 conditionals,
Residual R4, the EU-pin rows, earlier dated markers, or `privacy-policy.md`.

A new counsel-review record `knowledge-base/legal/audits/2026-10-counsel-review-9372.md` holds: the marker text and its
evidence table; the bounded Art. 5(2) statement for web-2's deleted plaintext volume (id 106466179, deleted through the
Hetzner API during the 2026-10-06 rebirth, take the date and run id from the apply run's log, bounded read; emptiness
evidenced by size only, about 16 MB; no zeroing step; no workspace data was ever routed to it; **not** claimed verified
empty); the "NOT DISCHARGED, lapses when web-2 receives weight or data" items (counsel-review 9377 C3 and C6, #9948,
#9949, #7992); and the #9642 pointer. A one-line statement was judged insufficient and a full web-1-style record
unwarranted (the web-1 record exists because that volume held every user's workspace source).

### D. Item 3 and item 4 disposition

| Item | Disposition in this PR | Tracking |
|---|---|---|
| 3a. Escrow preflight before the first destructive step | Verified done (workflow step order plus census test); recorded in the audit and in the #9372 closing comment | none needed |
| 3b. Passphrase-loss recovery for a data-bearing web-class host (Art. 32(1)(c)) | Not a condition of the flip (CLO). Stated in the row's `does_not_defend` and the audit as not discharged | **#9948**, milestone Phase 4: Validate + Scale, blocked by #7992 |
| 3c. `escrow=missing` re-escrow | Same | **#9949**, milestone Phase 4: Validate + Scale; related #9472 (fail-closed decision, owner-gated) |
| 4. #9642 emptiness-evidence strictness | **Surfaced, not decided.** PR body section "Owner decision needed" quoting #9642's three decisions, plus the observation that the real dispatches ran on 2026-10-06 under the unchanged thresholds and that PR 2 deletes the constants. The owner's options (accept retrospectively and close; keep open for a future rebirth tool; tighten before PR 2 retires the code) are listed neutrally | #9642 stays open until the owner rules |

### E. ADR and runbook records

- `ADR-140` dated addendum: the Layer A contract gains the indexed-binding rule, `key_chain`, `apparatus` and
  `multiplicity` (why, what each rejects, the opt-in compatibility rule).
- `ADR-263` dated addendum (append at the tail **after** #9925's addendum; take both on conflict): the grade, the flip, the
  claim boundary, that web-2 stays "provisioned, proof graded" at weight 0, and the pointers to #9948 / #9949.
  Status stays `adopting`.
- Runbook `web2-luks-rebirth-9372.md` closing row 2: append a dated "done by PR #9941" line (do not rewrite the row).

## Implementation Phases

### Phase 0 - Re-verify before writing anything (no writes)

0.1 `git fetch origin main`; `gh pr view` #9925, #9051, #9529, #8626 for merged/closed state; if #9925 has merged, rebase now.
0.2 Re-run the grader and the Hetzner volume read (commands under "Evidence pulled"). **Stop condition:** if the grader is not
PASS, or any probe row after the readiness row is non-green, stop: no flip, report on #9372.
0.3 Run `python3 scripts/lint-encryption-posture.py --repo-sweep` and `bash scripts/lint-encryption-posture.test.sh` for the
green baseline.
0.4 Read the apply run's log (bounded: `gh run view <id> --log | grep` with a pattern and `head`) for run id, dispatcher,
approver, delete step result and timestamps for the audit record. Never an unbounded log dump.

### Phase 1 - Linter commit (RED first, `cq-write-failing-tests-before`)

1.0 Prototype in the session scratchpad (never in the repo): the two scanner arms in A.3 against the real `workspaces-luks-provision.sh`, and a flipped ledger copy, to confirm the row can go green. If the mount-evidence arm cannot be made scoped and small, stop and re-plan before writing tests.
1.1 Write the matrix-derived fixtures and test cases first and watch them fail against the unmodified linter (cases below).
1.2 Schema: optional `device_binding.apparatus`, `device_binding.key_chain`, row-level `multiplicity`; `additionalProperties`
stays false.
1.3 Implement items A.1 to A.6 in the linter, each behind a `MUTATION-TARGET: MB-Ln start/end` marker.
1.4 Mutation battery rows MB-L1..MB-L8 (L1 indexed for_each equality, L2 pinned-file mount evidence, L3 token/secret config equality, L4 secret value hop, L5 password uniqueness, L6 unquoted resolver, L7 multiplicity set equality, L8 mandatory-when-indexed; prefix `MB-L` chosen so numbering cannot collide with #8626's MB-14..MB-25).
1.5 Green: baseline, new cases, TS-15 unchanged, real ledger unchanged and passing.

### Phase 2 - Ledger commit

2.1 Rewrite the row and the floor (B). 2.2 Run the linter on the real tree: PASS, `0 failing checks`. 2.3 Confirm the new count
of `available` rows is 3. 2.4 Confirm `registry-luks-live-8386.sh` and its test do not hardcode the floor in a way the bump
breaks (their text says "raise live_coverage_floor to 2" in a remediation message, not an assertion on the real value; run both
suites).

### Phase 3 - Legal commit

3.1 CLO agent drafts the marker; owner veto is recorded in the PR body (not assumed). 3.2 Apply the seven placements (C).
3.3 One-off check, not a committed test (the markers are append-only, so nothing remains to guard): verify the three cells carry a byte-identical marker after bold removal, with the span anchored from `IF AND WHEN web-2 has been rebuilt` through `describe it as encrypted.`, which is identical (314 characters) in all three cells today. 3.4 Create the counsel-review
record. 3.5 Run `bash scripts/lint-legal-registers.sh`. 3.6 Present-tense sweep of the engineering records for sentences the flip falsifies (grep `web-2` near `plaintext` over `knowledge-base/engineering/`, excluding archive, learnings, plans, specs): the `nfr-register.md` sentence gets a dated pointer here; the `web-host-replace.md` "LUKS rebirth" pointer line and the `.tf` comments ("converted by the gated rebirth") belong to PR 2, because editing a `.tf` file, even a comment, fires the push-triggered apply and needs its own apply-gate analysis.

### Phase 4 - ADR / runbook records

4.1 ADR-140 addendum (lands in commit 1 with the linter behaviour it describes, so a commit-2 revert leaves it true). 4.2 ADR-263 addendum (after rebase onto #9925 if merged). 4.3 Runbook row-2 dated line.
4.4 `bash plugins/soleur/test/c4-count-parity.test.sh`: green (no C4 change; see ADR/C4 section).

### Phase 5 - Tracking and owner surfacing

5.1 Confirm #9948 and #9949 exist with the milestone (done at plan time). 5.2 PR body "Owner decision needed" for #9642.
5.3 Comment on #9572 which prerequisites this PR closed (per-host split: dissolved, multiplicity instead; the two linter
gaps plus the mapper gap; the legal supersession; the floor) and which remain (HALT widening; import measurement now carried
by #9948). 5.4 Do **not** comment-close or close #9372 here.

### Phase 6 - Ship

Run the rollback simulation (see Rollback) before marking ready. Standard `soleur:ship` lifecycle. PR body: `Ref #9372` (no closing keyword; PR 2 closes it), the grader PASS line, the evidence
table, "Owner decision needed: #9642", and the not-claimed list. After merge: `postmerge`; the merge fires the CI ledger sweep
(already required on PRs), no Terraform apply is involved (no `.tf` file changes), so no infrastructure action is requested.

## Files to Edit

- `scripts/lint-encryption-posture.py` (A.1 to A.5; marker-delimited)
- `scripts/lint-encryption-posture.test.sh` (new fixtures, TS cases, MB-L battery)
- `scripts/encryption-posture-ledger.schema.json` (optional keys)
- `scripts/encryption-posture-ledger.json` (row rewrite, floor 3)
- `knowledge-base/legal/article-30-register.md` (three markers: PA-1 (e) twice, row (g) once)
- `knowledge-base/legal/compliance-posture.md` (markers: DPA-scope row, TS-1, T-1)
- `knowledge-base/legal/audits/workspaces-plaintext-destruction-record.md` (dated pointer under "Other copies of workspace data")
- `knowledge-base/engineering/architecture/nfr-register.md` (dated pointer after "web-2's workspaces volume is knowingly left plaintext-but-empty pre-flip")
- `knowledge-base/engineering/architecture/decisions/ADR-140-encryption-posture-as-a-design-time-default.md` (addendum; commit 1)
- `knowledge-base/engineering/architecture/decisions/ADR-263-guest-side-fresh-boot-luks-for-web-hosts.md` (addendum)
- `knowledge-base/engineering/operations/runbooks/web2-luks-rebirth-9372.md` (closing row 2 dated line)

## Files to Create

- `knowledge-base/legal/audits/2026-10-counsel-review-9372.md`
- `knowledge-base/project/specs/feat-one-shot-9372-web2-luks-ledger-closeout/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-9372-web2-luks-ledger-closeout/decision-challenges.md`

Not edited by PR 1 (checked): any `.tf` file (the `[each.key]` binding and the key pair are linter work, not layout work),
`model.c4` / `model.likec4.json`, `privacy-policy.md` and its mirrors, `AGENTS.md`.

## Open Code-Review Overlap

None. Queried open `code-review` issues against every planned path (linter, test, ledger, schema, both legal registers,
ADR-140, ADR-263, the runbook, the destruction record): zero matches.

## Sibling PR overlap and rebase plan

| PR | Overlap with this plan | Plan |
|---|---|---|
| #9925 (inngest sole-copy protection; MERGEABLE) | Ledger JSON: a different row (`inngest_redis_luks`, `does_not_defend` text). Article 30: PA-13 cells, different lines. compliance-posture: a different row. **ADR-263: both append at the tail** | Rebase this branch after #9925 merges; on the ADR-263 tail conflict keep both addenda in date order. Do not edit any #9925 hunk. Its ledger edit does not change the `available` count |
| #9051 (codex lifecycle) | Adds lines to `article-30-register.md` (hunks at ~69 and ~86, not in the conditional span) and one compliance-posture block at the end | Disjoint; resolve any context shift mechanically |
| #9529 (open web egress) | Adds one paragraph after line ~85 of `article-30-register.md` | Disjoint; re-anchor the marker by content, never by line |
| #8626 (stale draft, CONFLICTING) | Rewrites the linter and schema (host root disks, `records`, `multiplicity`) | Not rebased onto and not duplicated. This plan reuses its `multiplicity.instances` key names; its own reconciliation is its owner's, noted in the PR body. Mutation-row prefix `MB-L` avoids its MB-14..MB-25 |

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Flip the row with only the two #9572 linter fixes | Leaves the mapper join resolving through web-1's apparatus: a green lint that proves nothing about web-2's volume (ADR-140 rejects name-similarity joins) |
| Accept any sibling-file key pair in the same directory | The #6588 class: TS-15's plaintext row would find `workspaces_luks`'s pair in a sibling file and false-PASS. The explicit chain with a uniqueness rule is what keeps TS-15 red |
| Move the pair or the attachment into one file | Satisfies the check by layout; edits `.tf` surfaces pinned by tests (`fresh-boot-parity.test.sh`, `workspaces-luks.test.sh`); proves nothing |
| Extend the exception instead of flipping | The graded evidence exists; leaving a plaintext exception for a LUKS volume is itself a false record (Art. 5(2)) |
| Wait for #8626 | Stale since 2026-09-28, conflicting, 3,668 added lines; this flip needs only a small, opt-in subset |
| Two PRs (linter, then flip) | CTO's preference. Kept as the split trigger: if review of commit 1 needs a second round, cherry-pick commit 1 to its own PR (the commits are ordered for exactly that). Default is one PR because #9572 itself says "same change" |

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly: web-2 serves no traffic and holds no workspace data. The failure is a record that over-claims (a ledger or Article 30 sentence saying a volume is encrypted or recoverable when the evidence is formatted/opened plus probes), which weakens Art. 5(2) accountability and any later decision that leans on it.
- **If this leaks, the user's data is exposed via:** no new exposure vector (documentation and a lint). The indirect path is a later weight flip on web-2 that treats the green ledger as a recovery or reopen guarantee; that path needs a second failure (the anti-pooling gate, `lb-weight-gate.sh`, and ADR-263 "Known limits" hold web-2 at weight 0 until #9948 and #7992 are done).
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** not `single-user incident` because no user's data can reach web-2 through this change and the independent gate holds it at weight 0; ADR-263 itself carries `single-user incident` for the mechanism, and a reviewer who reads the flip as the green light for web-2 data should challenge this tier (recorded in `decision-challenges.md`).

## Architecture Decision (ADR/C4)

### ADR

The Layer A contract of the encryption-posture linter changes (indexed bindings, key chain, apparatus pin, multiplicity):
amend ADR-140 with a dated addendum (a plan task, Phase 4.1, not a follow-up). The flip's claim boundary is recorded as an
ADR-263 addendum (Phase 4.2). No new ordinal is taken.

### C4 views

None change. Checked against all three model files (`model.c4`, `views.c4`, `spec.c4`): external human actors involved: none
new; external systems: Better Stack, Doppler, Hetzner, GitHub already modeled (the `doppler -> hetzner`, `github ->
betterstack` and `github -> hetzner` edges exist); containers/data stores: the web-2 volume is described inside existing edge
prose; actor-to-surface access relationships: none change. Derived cardinalities on edge prose are unaffected (no workflow,
monitor or heartbeat is added or removed), to be confirmed by a green `plugins/soleur/test/c4-count-parity.test.sh`. A stale
sentence in `model.c4` ("the web-2 volume rebirth (#9372) is the dispatch-only, single-use ... inert until dispatched") is
PR 2's, with the single `model.likec4.json` regeneration.

### Sequencing

The ADR-263 addendum states the target as already true for the graded boundary only; nothing is postponed.

## Encryption Posture

```yaml
at_rest:
  - store: hcloud_volume.workspaces          # web-2's per-host /workspaces volume, Hetzner id 107059048
    mechanism: luks                          # LUKS2 container formatted/opened by the guest-side provisioner
    evidence: >-
      apparatus resolved mechanically by lint-encryption-posture.py through device_binding (volume, attachment, mapper
      `workspaces`, apparatus workspaces-luks-provision.sh, key_chain through the fresh-boot token and doppler_config
      prd_workspaces_luks_web); observed 2026-10-10: readiness row luks_arm=opened boot dd08ac9d, probe rows
      crypto_LUKS on /dev/mapper/workspaces on three distinct days, grader PASS
    defends_against: a seized, RMA'd or snapshot-imaged Hetzner block volume of web-2
    does_not_defend: >-
      a leaked credential; a read on the host while the mapper is open; loss of the passphrase (two copies, Doppler and
      unversioned Terraform state; no verified recovery, #9948); missing header escrow has no re-escrow step (#9949);
      reopen after reboot is not evidenced; the volume has no Hetzner delete protection; a future web host key is covered by
      static evidence only
    disclosed_as: not-publicly-claimed
    live_verification: available             # host-side luks-monitor rows via Better Stack, judged daily by web2_marker
in_transit: []                               # no connection is added or changed
# exception: removed with the flip (no plaintext-exception or cert_verification off row remains for this store)
```

Detector for the claim (so it does not outrun the evidence): the `web2_marker` job of `workspaces-luks-verify.yml` judges
web-2's newest readiness and probe rows daily, deletes the soak marker on RED and files `[ci/luks-verify-web2] web-2 LUKS
evidence is RED` (labels `luks/class-web2-red`, `priority/p1-high`), and its Sentry monitor `workspaces-luks-verify-web2`
alarms if the job stops running. PR 2 must keep this job and update only the comment that names the rebirth workflow as the
other marker-token holder.

## Guard Contract

### Guard 1 - Indexed volume binding

**Property.** A `luks` row binds to its attachment only through a literal reference to the claimed volume, with an index
form that provably selects the same instances.

**Assembly.** `attachment_binds_volume` (the singleton regex and the new indexed arm), its single caller `check_luks_row`, the
attachment block extractor `extract_resource_blocks` (flat-brace only), and the three call shapes the repo writes today: the
singleton `volume_id = hcloud_volume.workspaces_luks.id`, the indexed `hcloud_volume.workspaces[each.key].id`, and any
other index form. The chokepoint is `check_luks_row`; `run_sweep` is the only path that reaches it.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Index the volume with a literal key (`hcloud_volume.workspaces["web-1"].id`) | RED |
| 2 | Delete the `for_each`-equality condition from the indexed arm (MB-L1 wraps only that condition) | the fixture whose attachment and volume `for_each` differ flips from RED to PASS |
| 3 | Make `check_luks_row` return before the binding check (dispatch) so `0 checked` and exit 0 | RED (existing `check_positive_work_floor` and the parity-table count of resolved luks rows; the suite asserts the count) |
| 4 | Add a second luks row after a compliant first whose attachment is a sibling's | RED (the loop must check every row, not stop at the first) |
| 5 | Must-PASS non-canonical: indexed binding with a differently named `for_each` local and the identical expression on both blocks | PASS |

### Guard 2 - Key chain and password uniqueness

**Property.** A `luks` row's passphrase custody is the one the volume's host actually reads, and no passphrase is claimed by
two rows.

**Assembly.** `check_luks_row`'s key-material step (same-file pair, or `key_chain`), the Terraform resources named in the
chain (`hcloud_server.web` user_data map, `doppler_service_token.*`, `doppler_config.*`, `doppler_secret.*`,
`random_password.*`), and the global claim set built across all luks rows (explicit and implicit same-file claims). Members
drift (a new token, a new secret); the chokepoint is the chain verifier plus the claim set.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Point the token at web-1's `prd_workspaces_luks` config (MB-L3 deletes the config-equality hop) | RED |
| 2 | Change the secret's `value` to a different password's `.result` (MB-L4 deletes that hop) | RED |
| 3 | Two otherwise-valid luks rows claim one `random_password`, one explicitly through `key_chain`, one implicitly through its own file (MB-L5 deletes the uniqueness check; a dedicated fixture, because TS-15 fails at the binding check first) | RED |
| 4 | Row claims web-1's password (`workspaces_luks`) for web-2's volume | RED (the same uniqueness guard; no separate separation check exists) |
| 5 | Remove `key_chain` from the indexed row | RED ("indexed binding requires key_chain"); removing it from web-1's singleton row stays PASS (must-PASS differing from the canonical) |

### Guard 3 - Apparatus pinned to the provisioner file

**Property.** The mapper a `luks` row names is opened and mounted by the file the row names, not by any file that happens to
resolve the same mapper name.

**Assembly.** `scan_apparatus`, `scan_mount_evidence`, `resolve_mapper_operand` (quoted `${V:-d}`, quoted literal, and the new
unquoted literal), and every infra file that mentions `luksOpen` (`workspaces-cutover.sh`, `workspaces-luks-provision.sh`,
the registry, git-data and inngest cloud-init files). The chokepoint is the per-row resolution in `check_luks_row`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete `apparatus` from the flipped (indexed) row, the natural repair for a red lint | RED ("indexed binding requires apparatus"); a singleton row without it keeps its pre-change verdict (must-PASS differing from the canonical) |
| 2 | Point `apparatus` at web-1's `workspaces-cutover.sh` for web-2's row | RED (mount evidence must come from the pinned file) |
| 3 | Break the unquoted-assignment arm of the resolver (MB-L6) or the fstab-shaped mount-evidence arm (MB-L2) | RED |
| 4 | Rename the provisioner's `MAPPER_NAME=workspaces` to another value | RED (mapper mismatch) |

### Guard 4 - Multiplicity

**Property.** A row for a `for_each` volume names exactly the instances the expression produces, so a new host key cannot
inherit the claim.

**Assembly.** The row's `multiplicity`, the volume and attachment `for_each` expressions, `var.web_hosts` default keys in
`variables.tf`, and `local.plaintext_workspaces_hosts` in `server.tf`. Chokepoint: the multiplicity resolver (one supported
shape, fail-closed otherwise).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add a `web-3` key to `var.web_hosts` in a fixture (MB-L7 deletes the set-equality check) | RED |
| 2 | Change the local to a shape the resolver does not support | RED with the "declare ..." message |
| 3 | Dispatch: skip the resolver when `multiplicity` is absent on an indexed row | RED (absent declaration is itself a FAIL; MB-L8) |
| 4 | Declare `instances: ["web-2", "web-1"]` | RED |

Anchor (field 5): the ledger value and the code it grades are edited in one diff, so the floor proves consistency, not
integrity. ADR-141 deliberately rejects an identity pin on the three `available` stores (an honest re-ledgering must not
false-fail), so the anchor is review plus an outside signal: the `web2_marker` job and its RED issue are not editable by this
diff's ledger change. The reviewer checks the floor equals the number of `available` rows.

## Domain Review

**Domains relevant:** Legal, Engineering

### Legal (CLO)

**Status:** reviewed
**Assessment:** Supersede the same conditional span in three cells (Article 30 PA-1 (e), the cross-host row (g), the compliance-posture DPA-scope row) with one byte-equal marker, plus four related sentences and a pointer in the web-1 destruction record; leave premises, recovery sentences, C1/C2, R4, EU-pin rows, earlier markers and `privacy-policy.md` alone. Wording: formatted/opened plus green probes; never "at boot", "survives a reboot", "reborn". A bounded Art. 5(2) statement (not a full destruction record) for web-2's deleted plaintext volume. Recovery and re-escrow are conditions for web-2 receiving weight or data, not for the flip; record them as not discharged in the audit and the marker (#9948, #9949, #7992).

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Two non-obvious facts changed the design: the mapper join is not volume-bound (resolves through web-1's apparatus), and the web-1 probe does not cover web-2, so `available` needs the qualifying evidence text. Recommended opt-in `key_chain`, `apparatus` and `multiplicity` (same key names as #8626), linter commit first, flip after, rebase after #9925 for the ADR-263 tail; mutation rows per hop and per global guard. The CTO consult also served as the scoped advisor consult for this plan (the same decision points); no further advisor call was made.

No Product/UX surface: no UI file is created or edited. `soleur:gdpr-gate` was not run: no regulated-data code surface (schema, migration, auth, API route) is touched and none of the cross-controller triggers fire; the CLO consult covered the legal records.

## Scope Check

### Ask Mapping

<!-- lint-infra-ignore start: verbatim quote of the brief's own constraint (no dispatch, apply or Doppler write without go-ahead); the plan prescribes no such step -->

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "flip the hcloud_volume.workspaces ledger row to luks (live_verification: available, live_coverage_floor 2->3)" | Proposed Solution B; Phase 2 | mapped |
| 2 | "update the Article 30 / compliance-posture sentences conditioned on this event" | Proposed Solution C; Phase 3 | mapped |
| 3 | "the encryption-posture linter currently fails a luks row for that resource, and the ledger needs a per-host row split. Do those first." | Proposed Solution A; Phase 1; multiplicity replaces the split (dissolved, see Premise Validation) | mapped |
| 4 | "Hard deadline: the posture exception expires 2026-10-22." | Premise Validation row 2 (this row expires 2026-12-29; no extension needed) | descoped - justification: the premise is stale for this row; verified from the ledger |
| 5 | "retire web2-luks-rebirth.yml and web-host-reboot.yml with their tests/registrations" | Follow-up: PR 2 | descoped - justification: the brief and the parent assign it to PR 2, a later branch |
| 6 | "Check whether the retirement checklist items for apply-web-escrow-create are already done" | Premise Validation row "Escrow-create retirement checklist done"; PR 2 section | mapped |
| 7 | "confirm escrow preflight ordering, the passphrase-loss recovery path for a data-bearing web-class host (Art. 32(1)(c)), and the escrow=missing re-escrow step. Close each in a PR or file a tracked issue with a milestone" | Proposed Solution D (3a verified; #9948, #9949 filed) | mapped |
| 8 | "Open decision #9642 ... is owner-gated. Surface it to the operator; do NOT decide it." | Proposed Solution D row 4; Phase 5.2 | mapped |
| 9 | "When items 1-3 are merged and verified, comment the final state on #9372 and close it. Make no claim beyond what the graded rows show." | Follow-up: PR 2 (closing step); claim boundary throughout | mapped |
| 10 | "no workflow dispatch, terraform apply or Doppler write without the operator's explicit go-ahead; pull evidence from Better Stack/Sentry yourself" | Phase 0 evidence commands; no `.tf` change, no dispatch in PR 1 | mapped |
| 11 | "put `Closes #9372` in the PR body (on the final PR), not the title" | Overview; Phase 6 (`Ref #9372` here, closing keyword on PR 2) | mapped |

<!-- lint-infra-ignore end -->

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Linter: indexed binding; key chain | "the encryption-posture linter currently fails a luks row for that resource" (ask 3) | asked |
| Linter: apparatus pin | ask 3 | inferred - justification: the prototype showed the row passes only through web-1's apparatus; without the pin the "linter fails a luks row" fix would produce a green lint that proves nothing |
| Linter: multiplicity | "the ledger needs a per-host row split" (ask 3) | inferred - justification: stand-in for the dissolved split, so a new web host key cannot silently inherit the web-2 claim |
| Linter: unquoted-assignment and fstab-shaped mount-evidence arms, validator shape checks | ask 3 | inferred - justification: without them the pinned provisioner cannot resolve and a malformed row raises instead of failing |
| Linter: single-`for_each` rejection | ask 3 | inferred - justification: stops a nested second `for_each` forging expression equality |
| Ledger row rewrite from measured facts | ask 1 | asked |
| Legal markers (seven placements) | ask 2 | asked |
| Counsel-review record with bounded Art. 5(2) statement | ask 2 and "Make no claim beyond what the graded rows show" (ask 9) | inferred - justification: CLO ruling that the deleted plaintext volume's emptiness rests on size evidence only and the claim must say so |
| ADR-140 / ADR-263 addenda, runbook row-2 line | ask 2 | inferred - justification: `wg-architecture-decision-is-a-plan-deliverable`; the Layer A contract changes |
| #9948 and #9949 | ask 7 | asked |
| #9642 PR-body section | ask 8 | asked |
| Phase 0 re-verification and stop condition | ask 9 ("Make no claim beyond what the graded rows show") | asked |

### Split Assessment

- Subsystems touched: 3 - `scripts/`, `knowledge-base/legal/`, `knowledge-base/engineering/`
- Planned files: 15 | Estimated changed lines: about 750 (linter about 150, tests about 350, schema about 40, legal and ADR text about 200)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR, two ordered commits (linter first). Split trigger: if the linter commit needs a second review round or the estimate passes 800 lines, cherry-pick commit 1 into its own PR and rebase this one on it.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `python3 scripts/lint-encryption-posture.py --repo-sweep` exits 0 on the final tree, reports `0 failing checks`, and the real ledger's `hcloud_volume.workspaces` row reads `mechanism: luks`, `live_verification: available`, with no `exception` block.
- [ ] `live_coverage_floor` is 3 and exactly three rows read `live_verification: available` (`hcloud_volume.registry`, `hcloud_volume.workspaces_luks`, `hcloud_volume.workspaces`).
- [ ] `bash scripts/lint-encryption-posture.test.sh` passes; TS-15 (plaintext row citing a sibling's apparatus) is unchanged and still FAILs the row; every Guard Contract row above exists as a case or an MB-L mutation, and each MB-L mutation turns the same fixture from FAIL to PASS when its branch is deleted.
- [ ] A fixture reproducing the prototype (indexed binding relaxed, same-file pair removed, no apparatus pin) is RED under the shipped linter.
- [ ] The three conditional-span cells carry one identical marker (diff over the bold-stripped spans is empty); the added lines contain none of "at boot", "survives a reboot" or "reborn" in an affirmative claim about web-2's volume (a grep over the added lines returns only the marker's own negated sentence "not evidence that the volume reopens after a reboot", reviewed by eye), and the marker's date placeholder is resolved to the real date.
- [ ] `bash scripts/lint-legal-registers.sh` and `bash plugins/soleur/test/c4-count-parity.test.sh` pass. The new counsel-review record avoids the Art. 33 / Art. 4(12) tokens (`DETERMINATION_PATTERN` in `scripts/lint-legal-registers.sh`), so no breach-register waiver or row is needed; if the lint flags it anyway, the waiver and register row are added in the same PR.
- [ ] The parity table printed by `python3 scripts/lint-encryption-posture.py --report` is byte-identical before and after commit 1 (no existing row's verdict moves).
- [ ] `knowledge-base/legal/audits/2026-10-counsel-review-9372.md` exists with the run id, dispatcher, approver and timestamps read from the apply run's log, and the "not discharged" list citing #9948, #9949, #7992.
- [ ] ADR-140 and ADR-263 carry dated addenda; the ADR-263 addendum sits after #9925's if that merged.
- [ ] PR body: `Ref #9372` with no closing keyword in body or title; the grader PASS line; the "Owner decision needed: #9642" section (rendered by `ship` from `decision-challenges.md`, which also files the `action-required` issue; the body avoids the ship gate's deny tokens); the not-claimed list.
- [ ] `git diff --name-only origin/main...HEAD` (merge-base form) is a subset of: the files listed under "Files to Edit" and "Files to Create", the plan and its `tasks.md`, `specs/feat-one-shot-9372-web2-luks-ledger-closeout/session-state.md`, and the generated `knowledge-base/INDEX.md` if the pipeline rewrites it. In particular no `.tf` file, no workflow file and no Doppler-related file is in the set.
- [ ] #9572 carries a comment mapping its checkboxes to done / dissolved / carried by #9948.

### Post-merge (read-only)

- [ ] CI `encryption-posture` job green on main after merge.
- Observations, not criteria (they depend on external schedules): the grader still reads PASS when re-run read-only, and the next daily `web2_marker` run is green.

## Test Scenarios

- Given a web-class fixture (indexed volume and attachment sharing a `for_each`, a key pair in a sibling file, a token and secret on the same config, a provisioner with an unquoted `MAPPER_NAME`), when the row carries `key_chain`, `apparatus` and `multiplicity`, then the lint passes (unit).
- Given the same fixture with the attachment indexed by `["web-1"]`, then FAIL "does not attach" (unit).
- Given the web-class fixture with `apparatus`, `key_chain` or `multiplicity` removed from the indexed row (one case each), then FAIL naming the missing key (unit).
- Given the token's config pointing at web-1's config, then FAIL naming the hop (unit).
- Given two luks rows claiming one `random_password`, then FAIL on the second row (unit).
- Given the TS-15 fixture (plaintext volume, sibling's pair in another file), then FAIL as before (unit, regression for #6588).
- Given a fixture adding `web-3` to the host map, then FAIL until `multiplicity` is re-attested (unit).
- Given the real tree, then `--repo-sweep` passes and the parity table lists `hcloud_volume.workspaces` as luks (integration).
- Given the three legal cells, then a bold-stripped diff of the marker spans is empty and the forbidden-phrase grep over added lines is empty (unit, shell).
- Layer for every scenario: unit or integration; no e2e.

## Follow-up: PR 2 (cleanup; not part of this PR's tasks)

Separate branch, after PR 1 merges and after the owner has ruled on #9642 (retiring the workflow deletes the thresholds that
decision concerns). Retire `web2-luks-rebirth.yml` and `web-host-reboot.yml` with their tests and registrations, mirroring
the runbook closing rows 5 and the 2026-10-07 row-5 addendum and the 2026-10-04 checklist: the parity census
(`MAIN_ROOT_TF_WORKFLOWS` and the rebirth five-target describe block; **re-derive the expected count by running the
census**, the list holds five files today), `suite-shard-legs.tsv` and `suite-durations.tsv` (via
`scripts/regenerate-shard-manifest.py`, in both `scripts/` and `apps/web-platform/infra/`), `guard-vacuity-floor.test.sh`
`PROMOTED_FILES`, `model.c4` (the stale rebirth and reboot sentences on the `doppler -> hetzner`, `github -> hetzner` and
`github -> betterstack` edges) then `bash scripts/regenerate-c4-model.sh`, `_SUITE_BOUNDS` in
`apps/web-platform/infra/run-registered-suites.sh`, `scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh`, `READERS`
in `workspaces-luks-verify-workflow.test.sh`, `infra-credential-tiers-8209.md` rows, the ADR-241 consumer line, the
`web2_marker` job comment that names the rebirth workflow as the other marker-token holder, the two stale comments listed
in row 5, the runbooks (`web-host-reboot.md`, the reboot section of the rebirth runbook, and the "LUKS rebirth" pointer line in `web-host-replace.md` that says a plain replace of web-2 re-attaches the ext4 volume), and a retirement line in the
ADR-263 addendum of 2026-10-07 (and the 2026-10-04 addendum as the checklist asks). The escrow-create items are already
done (verified above); only the census arithmetic needs re-deriving. `scripts/web2-rebirth.sh flip-precondition` is deleted with its test, so its
"escrow-create stays absent" assertion needs a new home or an explicit drop decision in that PR. PR 2's body carries
`Closes #9372` (body, not title), and its post-merge step comments the final state on #9372 using only graded rows. Do not
start PR 2 inside this branch.

## Closing #9372 (item 5)

Conditions before the closing comment: PR 1 merged and verified (Post-merge criteria); PR 2 merged; #9948 and #9949 open
with milestones (tracked, not discharged); the owner has ruled on #9642 or has been told it stays open. The comment states
only: what the graded rows showed (grader PASS, dates, boot id), what the ledger and registers now say, what is not claimed
(reopen after reboot; any data on web-2; recovery; re-escrow), and the tracking issues. It does not say "LUKS-backed at boot".

## Rollback

Revert commit 2 (ledger, legal markers, ADR-263 addendum, nfr-register and runbook lines) on its own: the row returns to `plaintext-exception` with its
`expires_on: 2026-12-29`, the floor returns to 2, and the linter commit stays (all its new behaviour is optional for
singleton rows, so the lint stays green). Phase 6 simulates this before the PR is marked ready: in a scratch detached
worktree, `git revert --no-commit` the commit-2 SHA, then run `python3 scripts/lint-encryption-posture.py --repo-sweep`,
`bash scripts/lint-encryption-posture.test.sh` and `bash scripts/lint-legal-registers.sh`, and record the result in the PR
body. Legal markers are append-only: a revert removes the new markers, it never edits the superseded text.

## Risks and Sharp Edges

- A green lint after only the two #9572 fixes would have been a false proof (mapper join through web-1). The apparatus pin is what makes the row mean something; do not drop it to shrink the PR.
- `live_verification: available` is a floor-counted token, not a strength. Its qualifying text is part of the row and part of review.
- The three conditional-span cells drift if edited separately; edit them from one marker text and run the span diff.
- Never cite line numbers; Article 30 lines shift under #9051 and #9529 (content anchors only).
- The 2026-10-06 19:36Z `opened` readiness row shows a second boot of the web-2 host that evening; instance identity is a weak anchor (ADR-263 addendum). Do not describe it as a reboot test or a reopen proof.
- Phase 0's stop condition is real: the grader can fail between planning and merge (a non-green probe row spoils the soak).
- Deepen-plan note: a plan whose `## User-Brand Impact` is empty or placeholder fails deepen-plan Phase 4.6; the threshold here is stated with its challenge.
- The 2026-10-22 warnings printed by the linter are for other rows (#6897); they are not this PR's to fix and must not be "fixed" in passing.

## References

ADR-140, ADR-141, ADR-263 (addenda 2026-10-05 to 2026-10-08), ADR-119, ADR-282 (on #9925), runbook
`web2-luks-rebirth-9372.md`, `scripts/followthroughs/web2-luks-live-6931.sh`, `scripts/lib/web2-luks-rows.sh`,
`knowledge-base/legal/audits/2026-10-counsel-review-6931.md`, `2026-10-counsel-review-9377.md`. Issues: #9372, #9572, #9642,
#9948, #9949, #9472, #7992, #6931, #6897. PRs: #9941 (this), #9925, #9051, #9529, #8626, #9569, #9628, #9675, #9733, #9751.
