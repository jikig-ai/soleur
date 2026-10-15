# Brainstorm: separate the git-data plaintext wipe from the flip chain (2026-10-15)

Issue refs: Ref #10138, Ref #10136, Ref #6897. PR in flight: #10294 (draft). Status: read-only session; nothing dispatched, applied, written to Doppler or run against a volume.

## What We're Building

A wipe PR (PR-W, on #10294's branch) that destroys `hcloud_volume.git_data` WITHOUT waiting for the flip chain (#8573, #8609, #8209) or a 7-day soak, by replacing step W3's `flag=true` + soak with a separated, in-session predicate set. Plus the ADR-239 amendment and ledger-row correction that make the separation legitimate. The destroy itself stays a future operator-named dispatch.

## Measured state (2026-10-15, read-only)

- Hetzner API: plaintext volume 106867358 (created 2026-09-14, no delete protection) attached to server 170370833 beside LUKS volume 107140231 (created 2026-10-14T14:51:26Z). The ADR/ledger ids (server 169724272, volume 107102614) are gone after the rotate. Past measurement: 2026-10-12.
- Better Stack, newest `boot_complete` for `soleur-git-data`: 2026-10-14 14:52:17Z, `served_repos=0 plaintext_empty=yes plaintext_volume=present plaintext_journal=dirty luks_mounted=yes erasure_probe=yes fence_on_mapper=yes`. Boot-time only; `plaintext_empty=yes` means no repository entry at boot, not no residue.
- Ledger on `origin/main`: the git-data row and the three in-transit rows (two zot, Inngest) read `expires_on` 2026-11-12.
- Flip has not run (inferred: the rotate guard passed 2026-10-14). Residue (erased-user lock files, `.gc-cursor`), Hetzner snapshot retention, and web-2 are unmeasured.
- Open: #8573, #8609, #8209, #10296 (PR-R), #10297; drafts #10291, #9051, #8626 touch legal/ledger files.

## Why This Approach

Rulings, both 2026-10-15 (technical to CTO agent, legal to CLO agent; CLO is a v1 internal attestation, provisional to 2026-10-24):

- **Separable (CTO).** ADR-239 Consequences bullet 1 (rollback is flag-off only, data stays on LUKS) and D2 (volume never writable) mean flip status does not decide whether destroying the volume loses served data.
- **Separated predicate set (CTO, CLO-conditioned).** Read in-session, never from an input: flag does not read `true`; `GIT_DATA_LUKS_CUTOVER_AT` absent; `git_data_store_dirty_scan` returns `store_clean`; newest `boot_complete` newer than the server's creation with `served_repos=0`. A flip stamp or present stamp routes to the flip-chained variant with the soak intact; there is no soak-less fall-through after a flip.
- **No blocker gates it (CTO).** #8573 is the flag-write credential (wipe only reads the flag). #8609 is an accepted Tier-B residual to disclose in the ADR-241 note and record on #6897. #8209's `HCLOUD_TOKEN` rotation is a sequencing point only.
- **Soak (CLO).** Not a legal gate for the separated wipe (Art. 5(1)(e), 17, 32); it was an engineering rollback-safety gate. Each extra retention day is an Art. 5(1)(e) overrun against our own date.
- **Rehearsal (CTO).** PR-W needs no paid rung-2 rehearsal; the empty-id rehearsal is PR-R (#10296), on throwaway infrastructure, and binds PR-C. PR-W carries stub suites and a live read-only `wipe_check`. W9/W11 first run live in the real dispatch.
- **`wipe_check` runs the counts-only dm-snapshot layout listing (CLO position).** Otherwise it returns green with the refusal path unexercised. Counts only, origin unwritten, output ends "NOT authorization", result recorded as a dated measurement. (Engineering is the CTO's.)

## Key Decisions

| Decision | Source |
|---|---|
| Separate the wipe from the flip chain | CTO 2026-10-15; CLO 2026-10-13 and 2026-10-15 |
| Soak survives only in the flip-chained variant | CLO 2026-10-15 |
| Wipe-PR evidence record: pre-state read, predicate verdicts with the 2026-10-14 `boot_complete` row quoted and glossed, run record, residue count or "unmeasured", copies "unmeasured; 404 is the end event for the device only" | CLO 2026-10-15 |
| ADR-239 amendment supersedes only "gated by the flip chain" (2026-10-09), "bound to the flip chain" and the blocker chain (2026-10-12), with a `Superseded 2026-10-15 (#6897)` marker in every sibling file; takes effect on merge of the carrying PR | CLO 2026-10-15 |
| Ledger row `hcloud_volume.git_data`: rewrite `defends_against`, `justification`, `reevaluate_when`, `live_verification` (re-dated 10-15 read; 10-12 kept as past measurement). `expires_on` stays 2026-11-12 | CLO 2026-10-15 |

## Schedule (CTO, inferred; 11-12 is a Thursday)

ADR amendment + CLO sign-off wording 10-19 to 10-22; PR-W merged 10-30; `wipe_check` green 11-02; PR-R rehearsal 11-02, evidence PR 11-04; PR-C READY 11-04; wipe dispatch target 11-05, last 11-09; PR-C merged by 11-12 (lint fails from 11-13). Operator must be asked to name the command by 11-02. CLO to be told the same day any milestone is missed; latest notice of a slip is Friday 11-06 end of day.

## Open Questions

- The 2026-10-24 CLO re-ruling still owns DPD 2.3(o)'s packet-filter sentence, DPD 10.3(b) disclosure, the three in-transit ledger rows, and the #10136 follow-ups (`list-runs.ts` raw bearer, NFR-026, lint polarity gap, DPA inherited line).
- Whether the `wipe_check` listing can run without writing the origin (CTO to confirm in the build).
- Who runs the R5 `HCLOUD_TOKEN` rotation relative to the wipe (before it, or after PR-C), since its plan-only canary is refused by the post-wipe wedge (CTO, inferred).
- Hetzner snapshot/backup retention for the destroyed volume: unmeasured, inherited from ADR-239.
- Not claimed anywhere here: reopen, passphrase-loss recovery (#9948), re-escrow (#9949), the state-restore substrate (#7992), or emptiness for web-2.

## Domain Assessments

**Assessed:** Engineering, Legal.

### Engineering

**Summary:** Ruled by CTO agent, 2026-10-15: separable, no open blocker gates it, feasible before 2026-11-12 with about one failed cycle of slack. Biggest risk: the layout listing first runs inside the counting dispatch unless `wipe_check` runs it.

### Legal

**Summary:** Ruled by CLO agent, 2026-10-15 (v1 internal attestation, provisional to 2026-10-24): no soak required for the separated wipe; destruction needs a dated, measured/policy/inherited record that claims nothing about copies.

## User-Brand Impact

- **Artifact:** the destruction of `hcloud_volume.git_data` (volume 106867358) and the erasure record for users whose identifiers may sit on it.
- **Vector:** an irreversible delete of the wrong volume, or an erasure record that overclaims, harms a user or breaches an Art. 5(2) accountability duty.
- **Threshold:** `single-user incident`.
