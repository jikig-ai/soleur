---
title: "Counsel review audit — #6894 / PR #8248 (ADR-142 additive blue-green LUKS cutover apparatus for the Inngest Redis AOF: PA-13 §(e) route amendment; PA-21 / PA-22 §(f) Redis-AOF store amendments; encryption-posture ledger plaintext-row reassessment + new sibling row)"
type: counsel-review
date: 2026-09-18
issue: 6894
pr: 8248
status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)
signed_off_at: 2026-09-18
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; the operator retains an optional veto)"
disposition: "DISCHARGED subject to THREE in-PR text corrections (C1–C3, below) that the lead applies before merge. Three legal artifacts in scope: knowledge-base/legal/article-30-register.md (PA-13 §(e) dated amendment bracket; PA-21 §(f) and PA-22 §(f) dated amendment brackets), scripts/encryption-posture-ledger.json (hcloud_volume.inngest_redis reassessment; new hcloud_volume.inngest_redis_luks row), and — read for consistency, not attested — the ADR-142 2026-09-18 amendment. The register diff is additions-only inside the three cells (no deleted token, no Status cell, no docs/legal/** or Eleventy mirror file). Every implementation claim was checked against the shipped bodies (inngest-redis-luks.tf resources hcloud_volume.inngest_redis_luks / hcloud_volume_attachment.inngest_redis_luks / doppler_secret.inngest_redis_luks_key; inngest-luks-cutover.sh copy_store / swap_forward / rollback / finish_after_swap and its state table; betterstack-logs-alerts.tf logtail_exploration_alert.inngest_luks_wrong_volume; inngest-redis.conf header; ADR-100 2026-09-15 addendum; the runbook), not against the plan. Encryption is claimed NOWHERE as present: all three register cells and both ledger rows say plaintext today, and the published Privacy Policy / GDPR Policy / DPD scope every LUKS at-rest claim to the workspaces volume, so nothing this PR ships contradicts a published disclosure. Two defects and one omission require correction, all inside or adjacent to text this PR inserts: (C1) the PA-13 §(e) cell this PR amends still carries the pre-#8191 sentence that the SERVING substrate is the co-located web host, while the bracket this PR adds cites a 442-key store on the dedicated host — the cell now contradicts itself and the stale sentence over-claims protection (it would place the personal data on the LUKS workspaces volume); (C2) neither PA-21/22 §(f) nor PA-13 §(e) says that after the cutover TWO copies of the same AOF exist concurrently, one plaintext, for a bounded window with a dated expiry — the ledger and ADR-142 say it, the Art. 30(1)(g) record does not; (C3) PA-21/22 §(f) 'no automatic deletion … bounded by Redis rewrite and by the single authorised FLUSHALL' misstates the measured keyspace (431 of 442 keys carry Redis TTLs per the same PR's own inngest-redis-luks.tf rationale) and names as a future bound a FLUSHALL that already ran on 2026-09-15. No Art. 33 and no Art. 34 duty arises: the merge creates an empty, unformatted volume and copies nothing; the later cutover is a controller-internal security-measure transition, not an Art. 4(12) event."
blocking_findings: []
required_before_merge_DISCHARGED:
  - "C1 — PA-13 §(e): append a `[Superseded 2026-09-15 (#6178/#8191) …]` marker under the 'substrate in the SERVING path today is the co-located deployment on the web host' sentence (exact text under §Conditions). Pre-existing staleness, but this PR edits the cell and its new bracket depends on the opposite fact."
  - "C2 — PA-21 §(f) and PA-22 §(f) amendment brackets (and, in one clause, PA-13 §(e)): state the two-concurrent-copies backstop window with its expiry (exact text under §Conditions)."
  - "C3 — PA-21 §(f) and PA-22 §(f): correct the retention sentence — TTL keys exist and the #6178 FLUSHALL is past (exact text under §Conditions)."
optional_precision_notes:
  - "O1 — The published DPD §2.3 carries the same stale 'substrate in the serving path today is the co-located deployment on the web host' sentence (twice). Out of this PR's scope (docs/legal/** untouched; touching it engages the five #7387 gates) and predates this PR (#8191 did not carry its ADR-100 supersession into the legal corpus). File a compliance/ follow-up; do not fold it into this PR."
  - "O2 — PA-21/22 §(f) 'the register's only statement about this device was PA-13 §(f)' is imprecise: PA-13 §(e) is the register's principal description of the device (plaintext ext4, ledgered exception); §(f) is the statement about personal-data-bearing scope. The point the bracket makes (the PA-13 scoping was never re-derived for unhashed payloads) is correct. Non-blocking."
  - "O3 — No compliance-posture.md row rides this PR, unlike the #8189/#8205 precedents. The register amendments and ledger rows are the substantive record; a posture row would be bookkeeping. Recommended, not conditioned."
  - "O4 — ADR-142 'No key escrow' rests on 'the AOF is transient and self-healing', while the same ADR (and the tf rationale) records armed reminders at unbounded future fire-times. After #8285 retires the plaintext backstop, INNGEST_REDIS_LUKS_KEY in Doppler soleur-inngest/prd is the sole opener and its loss is an Art. 32(1)(c) availability loss of every armed reminder. Engineering decision, not a register defect — flagged for the CTO; the register need not recite it until the backstop is gone."
  - "O5 — The ledger's plaintext-row expires_on 2026-10-22 is byte-unchanged from main (verified); the 'expires_on_not_extended' clause holds. The new sibling row shares the date, so a cutover that has not been measured by then expires BOTH exceptions together — which is the correct failure mode."
attests:
  - "knowledge-base/legal/article-30-register.md — the three 2026-09-18 AMENDMENT (#6894) brackets added by PR #8248 ONLY (PA-13 §(e); PA-21 §(f); PA-22 §(f)), as corrected by C1–C3"
  - "scripts/encryption-posture-ledger.json — the hcloud_volume.inngest_redis row's 2026-09-18 reassessment (live_verification, exception.justification, reassessed_on, reevaluate_when) and the new hcloud_volume.inngest_redis_luks row"
does_not_attest:
  - "knowledge-base/engineering/architecture/decisions/ADR-142-*.md 2026-09-18 amendment and ADR-100 (engineering records; relied upon for the serving-path fact and the four design choices)"
  - "knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md (operator record, relied upon for retention/backstop language)"
  - "The Terraform, the cutover FSM, the alert and the tests themselves (technical controls; counsel attests the register's statements about them, not their correctness)"
art_33_triggered: false
art_34_triggered: false
re_evaluation_triggers: "(1) The cutover measured (#8295 closes): the ledger sibling row flips to luks and the plaintext row is rewritten as a retained backstop (#8296) — re-attest both register cells at that commit, and verify the cell does not claim encryption before the flip commit lands. (2) #8285 (backstop retirement, expires 2026-10-22): on detach+destroy, remove the two-copies clause C2 adds and close the plaintext exception; if 2026-10-22 passes with the backstop attached, the exception has EXPIRED and the register must say so. (3) Any rollback (INNGEST_LUKS_CUTOVER = rolled-back): the encrypted volume then holds a stale second copy — the two-copies clause inverts and must be re-derived. (4) O1's DPD follow-up landing. Standing external-counsel triggers unchanged (first arms-length user, EEA-out, regulated industry)."
---

# Counsel review audit — #6894 / PR #8248 (ADR-142 additive blue-green LUKS cutover apparatus)

This file is the load-bearing evidence for the ship Phase 5.5 Counsel-Review CLO-Attestation Gate on
PR #8248 (issue #6894). The gate fired on `knowledge-base/legal/article-30-register.md` under a
`single-user incident` brand-survival threshold. The CLO agent is the v1 attestation authority; the
operator holds an optional veto.

## Scope and limit check

- **Additions only inside three cells.** PA-13 §(e) gains one bracket inserted mid-cell; PA-21 §(f)
  and PA-22 §(f) each gain one bracket appended at the cell's end. No deleted token in any register
  cell; no Status cell; no lawful-basis cell; no `docs/legal/**` or Eleventy mirror file engaged
  (`git diff origin/main...HEAD --stat -- docs/legal plugins/soleur/docs/pages/legal` is empty).
- **Merge-conditioning is stated, not smuggled.** Both §(f) brackets say the apparatus "merges inert
  in the same change" and that the cutover is "a separate reviewer-gated dispatch tracked at #8295";
  PA-13 §(e) says "the apparatus is still inert until a reviewer-gated dispatch runs (#8295)". No
  past-tense claim about this PR's merge. Trackers #6894, #8285, #8294, #8295, #8296 are all OPEN
  (`gh issue view`, read-only) and #8285's title carries the 2026-10-22 expiry.
- **No `[DRAFT — pending CLO/counsel review` markers** in the PR diff (`grep -c` → 0).
- **Production untouched by this review.** No doppler / terraform / hcloud / gh write was run.

## Drift table

| # | Claim added | Checked against (file / anchor) | Verdict |
|---|---|---|---|
| D1 | PA-13 §(e): the recut route "is no longer the one this device takes"; ADR-199 permits the recut only against a store measured EMPTY; "this store measures 442 keys" | `inngest-redis-luks.tf`, rationale above `resource "hcloud_volume" "inngest_redis_luks"`: "MEASURED 2026-09-17 … redis_keys=442, redis_expires=431 … G13 refuses, and it refuses permanently" | **Holds** |
| D2 | PA-13 §(e): the additive route is "a second volume, a byte-proven copy, a mount swap, and the plaintext volume retained as the rollback backstop" | `hcloud_volume.inngest_redis_luks` + `hcloud_volume_attachment.inngest_redis_luks` (created alongside, staged, never `/mnt/data` until the swap); `copy_store` (`cp -a "$src/." "$dst/"` — whole mount); `t2_verify` (listing + sha256 + bytes + `redis-check-aof`); `swap_forward` (umount plaintext, luksOpen canonical, mount, pointer LAST); `rollback` (`refuse rollback-no-backstop` if the plaintext alias is absent — the backstop is a precondition, so it is retained by construction) | **Holds** |
| D3 | PA-13 §(e): "the device is still plaintext, and the apparatus is still inert until a reviewer-gated dispatch runs (#8295)" | Nothing in the diff formats or copies at merge; the FSM's `(unset)` state is a no-op; `op=luks-cutover` holds in the `inngest-cutover` environment (runbook §header); #8295 OPEN | **Holds** |
| D4 | PA-13 §(e), UNTOUCHED neighbour sentence: "the substrate in the SERVING path today is the co-located deployment on the web host … 'has served nothing since 2026-07-30'" | ADR-100 status block: "**Superseded 2026-09-15:** the cutover was re-run and completed"; 2026-09-15 addendum: host FSM `done`, app repointed to `http://10.0.1.40:8288` (#8191). The register carries no marker. D1's 442-key reading is only coherent if the dedicated host serves | **STALE and now self-contradictory in the amended cell → C1** |
| D5 | PA-21/22 §(f): the Inngest queue + run-state live in Redis, Postgres holds config/history (`inngest-redis.conf` anchor comment); AOF on `hcloud_volume.inngest_redis` at `/mnt/data` on the dedicated host | `inngest-redis.conf` header: "Inngest's queue + run-state live in Redis (Postgres holds only config/history"; `inngest-luks-cutover.sh` `MNT` default `/mnt/data`; ADR-100 2026-09-15 addendum places the serving substrate on the dedicated host | **Holds** |
| D6 | PA-21/22 §(f): ADR-142 characterises the payloads as in-flight job data — user prompts and agent output; the ledger carries the volume as its highest-sensitivity row | Ledger `hcloud_volume.inngest_redis` `does_not_defend` ("in-flight job payloads (user prompts and agent output)"), `exception.justification` ("highest-sensitivity plaintext store") | **Holds** |
| D7 | PA-21/22 §(f): "the register did not name it" for these activities; PA-13 §(f)'s not-personal-data-bearing scoping was never re-derived | `git show origin/main:…/article-30-register.md` — `hcloud_volume.inngest_redis` / "append-only file" appear only in PA-13 §(e)/(f) and PA-14; PA-13 §(f) scopes its clause "for THIS activity" | **Holds** (O2 on "only statement … §(f)") |
| D8 | PA-21/22 §(f): "no automatic deletion … AOF content is bounded by Redis rewrite and by the single authorised `FLUSHALL` of the #6178 cutover FSM, not by a schedule" | tf rationale: `redis_expires=431` of 442 (keys with TTL); runbook §4 "volatile keys may have expired"; ADR-100 2026-09-15 addendum: `INNGEST_CUTOVER_FLIP=done` — the one authorised FLUSHALL has RUN; AOF rewrite compacts and deletes nothing | **FALSE in two limbs → C3** |
| D9 | PA-21/22 §(f): "PLAINTEXT ext4 as of this amendment … This cell asserts no encryption until that flip is made" (#8296) | Ledger plaintext row `mechanism: plaintext-exception` unchanged; sibling row `plaintext-exception` by design; #8296 OPEN | **Holds** |
| D10 | Ledger plaintext row: the probe's `data_mount_devid` still pinning THIS volume post-cutover is what `logtail_exploration_alert.inngest_luks_wrong_volume` pages on; the sibling row is the one that flips; retirement tracked with expiry in #8285 | `betterstack-logs-alerts.tf` `resource "logtail_exploration_alert" "inngest_luks_wrong_volume"`, `local.inngest_luks_wrong_volume_alias = "scsi-0HC_Volume_${hcloud_volume.inngest_redis_luks.id}"`, `position(… 'data_mount_devid=<luks alias> ') = 0`; gated by `var.inngest_luks_cutover_complete` (ships paused); #8285 OPEN, expiry in title | **Holds** |
| D11 | Ledger plaintext row: `expires_on` "DELIBERATELY unchanged"; `reassessed_on` moves to 2026-09-18 | `git show origin/main:scripts/encryption-posture-ledger.json` — `expires_on: 2026-10-22` present before and after; only `reassessed_on`/`reevaluate_when`/`justification`/`live_verification` changed | **Holds** |
| D12 | Ledger new row: "at merge the volume does not exist at all"; born RAW (no `format`); luksFormatted by cloud-init on first boot that sees it; mounted at a STAGING path; mechanism flips only in the follow-up commit that records an observed cutover boot | `hcloud_volume.inngest_redis_luks` has no `format` attribute (rationale: "NO `format` ATTRIBUTE, AND THAT IS LOAD-BEARING"); `STAGING_MNT` default `/mnt/data-luks`, `STAGING_NAME=inngest-redis-staging`; `assert_precutover_topology` requires the staging mapper backed by the additive volume | **Holds** — the row deliberately lags; no encryption claimed |
| D13 | Published disclosures: no claim that the Inngest/Redis store is encrypted at rest; no retention window the backstop would breach | `docs/legal/{privacy-policy,gdpr-policy,data-protection-disclosure}.md` + mirrors: every "LUKS-encrypted (encryption at rest)" sentence is scoped to the workspaces volume; "AES-256-GCM" is scoped to API keys; DPD §2.3 says Inngest state is held in three stores "none of which self-expires" — consistent with no store-level window | **Holds** (O1 for the DPD's separate stale serving-path sentence) |
| D14 | Art. 30(1)(g) / Art. 32: the retained plaintext backstop is recorded as a bounded security-measure transition | Ledger plaintext row (`RETAINED PLAINTEXT BACKSTOP … #8285 … expires 2026-10-22`); ADR-142 amendment §1 ("deliberate and bounded … tracked with an expiry in #8285 … DETECTED rather than assumed"); register: "retained as the rollback backstop" / "the retained plaintext backstop at #8285" with NO expiry and NO statement that a second full copy exists | **Partial → C2** |

## Findings

- **F1 (C1).** The serving-path sentence. PA-13 §(e) was corrected on 2026-09-03 to say the
  co-located web host is the serving substrate and the dedicated host "has served nothing since
  2026-07-30". ADR-100's 2026-09-15 addendum supersedes that: the #6178 flip reached `done` and #8191
  repointed the app to the dedicated host. #8191 did not carry the supersession into the register.
  This PR now inserts, in the same cell, a reading of 442 keys / 431 armed reminders on the dedicated
  host's volume — which is only a populated store because that host serves. The cell therefore says
  the personal data is on the web host's LUKS workspaces volume AND that it sits in a 442-key plaintext
  store on the dedicated host. The first is the over-claim of protection; the second is true. Per the
  register's own discipline (superseded sentences get an in-place dated marker, never silent
  contradiction — `breach-register.md` 2026-06-29 precedent, PR #8153 learning), a marker is required.
  Ruled a correction, not a block: the fix is an append-only marker in a cell this PR already edits.
- **F2 (C2).** Two copies. `copy_store` copies the whole mount; `swap_forward` unmounts the plaintext
  volume but neither detaches nor wipes it; `rollback` refuses without it. So from the cutover until
  #8285 executes, the SAME AOF — user prompts, agent output, armed reminders — exists twice, once in
  plaintext. The ledger says this in terms; ADR-142 §1 says it in terms; the register says "retained
  as the rollback backstop" and cites #8285 without the expiry. Art. 30(1)(g) asks for a general
  description of the security measures; a second plaintext copy of the highest-sensitivity store,
  attached for up to five weeks, is a measure-transition fact the register should carry with its
  bound. Correction, not block: text this PR inserts, additive.
- **F3 (C3).** Retention. "No automatic deletion" is the PA-27 §(f) / PA-13 §(f) determination about
  the Inngest STORE (no `--history-retention`, no sweep) and remains true at store level. Applied to
  the Redis keyspace it is false in this PR's own evidence: 431 of 442 keys carry TTLs and Redis
  removes them on expiry. "Bounded by Redis rewrite" is wrong in kind — `BGREWRITEAOF` compacts the
  file to the live dataset and deletes no key. "The single authorised `FLUSHALL` of the #6178 cutover
  FSM" was a real bound until 2026-09-15, when it ran; the store was then repopulated and no further
  FLUSHALL is authorised (`inngest-cutover-flip.sh` state table: `done` does NOT re-FLUSHALL). The
  sentence names a spent bound as a live one. Direction: it over-states retention (claims data is
  kept longer than it is), so not an over-claim of protection — but a false Art. 30(1)(f) statement
  cross-referenced by the same PR's tf rationale. Correction, not block.
- **F4.** Lawful basis. The diff does not touch any Lawful-basis cell; PA-13 (Art. 6(1)(b) + (f)),
  PA-21 (Art. 6(1)(b)), PA-22 (Art. 6(1)(b) + (f) with the contributor-PII balancing) are unchanged.
  Encrypting a store at rest, and briefly holding a second copy of it inside the same controller,
  same datacenter, same Art. 28 processor (Hetzner AVV), introduces no new purpose, recipient,
  transfer or category. No lawful-basis change is required.
- **F5.** Art. 33/34. At merge nothing is copied — the new volume is unformatted and empty. The later
  cutover moves data between two volumes of the same controller on the same host; a rollback
  reverse-copies. None of that is destruction, loss, alteration or unauthorised disclosure
  (Art. 4(12)). The plaintext backstop being retained is the CONTINUATION of the existing ledgered
  exception, not a new exposure. No breach-register row; no notification duty.
- **F6.** The ledger rows are correctly asymmetric. The plaintext row keeps `plaintext-exception`,
  keeps its expiry, and re-derives `reevaluate_when` so that it can never flip to `luks` (the volume
  never becomes encrypted under this route); the sibling row is `plaintext-exception` about a device
  that does not exist and says so, with the flip reserved for a commit that records an OBSERVED
  cutover boot. Both rows carry #6894 and 2026-10-22. The lagging-record direction is the safe one.
- **F7.** No published disclosure is contradicted. Every at-rest encryption sentence in the Privacy
  Policy, GDPR Policy and DPD (canonical and mirror) is scoped to the workspaces volume or to API
  keys; none says "all stores" or names the Inngest/Redis store as encrypted. The DPD's "none of
  which self-expires" is a store-level statement and survives C3's key-level qualification.

## Conditions

Three corrections. All are to text this PR inserts or to the cell it edits; all are append-only
or replace-in-place within the 2026-09-18 brackets. Apply to `knowledge-base/legal/article-30-register.md`.

**C1.** PA-13 §(e). Immediately after the sentence

> ADR-100 records that the dedicated host "has served nothing since 2026-07-30", so naming it alone would describe the configuration rather than the processing.

append:

> **[Superseded 2026-09-15 (#6178 / #8191); marker added 2026-09-18 (#6894): the cutover was re-run and completed on 2026-09-15 — the host FSM reached `done` and the app was repointed to the dedicated host (ADR-100, 2026-09-15 addendum). The DEDICATED host is the serving substrate today, which is why the store measured in the 2026-09-18 amendment below is populated; the co-located deployment's surfaces described in this limb are the superseded configuration. Everything else in this limb about the dedicated host's resources stands.]**

**C2.** (a) PA-21 §(f) AND PA-22 §(f), inside the 2026-09-18 bracket, immediately after

> …the ledger flip that would let this cell claim encryption at #8296, and the retained plaintext backstop at #8285.

append:

> **Two copies, bounded:** the cutover is additive — it byte-copies the whole `/mnt/data` mount onto `hcloud_volume.inngest_redis_luks`, proves the copy identical, and swaps the mount, leaving `hcloud_volume.inngest_redis` attached and intact as the rollback backstop (`inngest-luks-cutover.sh`, `swap_forward` / `rollback`). From the cutover until that backstop is detached and destroyed, TWO copies of the same AOF exist concurrently, one of them plaintext. The backstop's retirement is tracked at #8285 with an expiry of 2026-10-22; this cell is amended when it lands, and reads as EXPIRED if that date passes with the backstop attached.

(b) PA-13 §(e), inside the 2026-09-18 bracket, replace

> …and the plaintext volume retained as the rollback backstop.

with:

> …and the plaintext volume retained, attached and intact, as the rollback backstop — a second, plaintext copy of the same AOF that exists concurrently with the encrypted one until retired (#8285, expires 2026-10-22).

**C3.** PA-21 §(f) AND PA-22 §(f), inside the 2026-09-18 bracket, replace

> **Retention:** no automatic deletion (the `--history-retention` window PA-13 §(f) retracted was never configuration-backed). AOF content is bounded by Redis rewrite and by the single authorised `FLUSHALL` of the #6178 cutover FSM, not by a schedule.

with:

> **Retention:** no store-level retention window (the `--history-retention` window PA-13 §(f) retracted was never configuration-backed) and no scheduled deletion. Individual keys carry Redis TTLs — 431 of the 442 keys measured 2026-09-17 (`inngest-redis-luks.tf`, rationale above `hcloud_volume.inngest_redis_luks`) are the armed-reminder set and are removed by Redis on expiry; the remainder persists indefinitely. AOF rewrite compacts the file and deletes no key. The one authorised `FLUSHALL` of the #6178 cutover FSM ran on 2026-09-15 (ADR-100 addendum) and is not a future bound.

No other text change is required. O1–O5 are non-blocking.

## Verification commands (re-runnable from the worktree)

- `grep -n 'Superseded 2026-09-15' knowledge-base/engineering/architecture/decisions/ADR-100*.md` → status-block supersession (C1).
- `grep -c 'served nothing since 2026-07-30' knowledge-base/legal/article-30-register.md` → 1 with no adjacent `Superseded` marker before C1 (C1).
- `grep -n 'redis_keys=442, redis_expires=431' apps/web-platform/infra/inngest-redis-luks.tf` → the measured keyspace (D1, C3).
- `grep -n 'cp -a -- "\$src/\." "\$dst/"\|rollback-no-backstop' apps/web-platform/infra/inngest-luks-cutover.sh` → whole-mount copy; backstop is a rollback precondition (D2, C2).
- `grep -n '^resource "logtail_exploration_alert" "inngest_luks_wrong_volume"' apps/web-platform/infra/betterstack-logs-alerts.tf` → the wrong-volume alert (D10).
- `git show origin/main:scripts/encryption-posture-ledger.json | grep -n '"expires_on": "2026-10-22"' | head -3` → plaintext-row expiry unchanged (D11).
- `grep -rnoiE '.{100}(LUKS-encrypted \(encryption at rest\)|encrypted at rest).{60}' docs/legal/*.md | grep -vi workspace` → empty: every at-rest sentence is workspace-scoped (D13).
- `grep -oE '[^.]{0,80}serving path today[^.]{0,80}' docs/legal/data-protection-disclosure.md` → two stale sentences (O1).
- `for n in 6894 8285 8294 8295 8296; do gh issue view $n --json state -q .state; done` → OPEN ×5.
- `git diff origin/main...HEAD | grep -c 'DRAFT — pending'` → 0.

## Lead application record

Applied 2026-09-18 by the ship-phase lead, in `knowledge-base/legal/article-30-register.md`, as a
scripted replace-in-place with a uniqueness assertion on each anchor (C1 ×1, C2a ×2 — PA-21 and
PA-22 — C2b ×1, C3 ×2). Verification: `grep -c 'Two copies, bounded:'` → 2; `grep -c 'Superseded
2026-09-15 (#6178 / #8191)'` → 1; `grep -c 'is not a future bound'` → 2; the withdrawn sentence
`bounded by Redis rewrite and by the single authorised` → 0. O1 (the DPD's stale co-located
serving-path sentence) is pre-existing and left for a follow-up; not filed from this PR, which is
already net-positive on the issue queue — carried in the PR body's ship-gate record.
