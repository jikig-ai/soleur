---
title: "Counsel review audit — #8043 / PR #8052 (Art. 30 PA-36 added, declared-not-live; PA-2 §(e) and the header surface list amended)"
type: counsel-review
date: 2026-09-11
issue: 8043
pr: 8052
status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)
signed_off_at: 2026-09-11
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; the operator retains an optional veto)"
disposition: "DISCHARGED subject to ONE in-PR text correction (C1, below) that the lead applies before merge. One artifact in scope: knowledge-base/legal/article-30-register.md — the new PA-36 (limbs (a)–(h) + Status), the PA-2 §(e) wording change, the PA-2 replication-row cross-reference, the header surface list, the Hetzner vendor row, and Register Maintenance item 13. Every implementation-detail claim in PA-36 was verified against the shipped body (the three wrappers, cloud-init, bootstrap, git-data.tf, account-delete.ts, git-auth.ts, git-data-replication.ts, issue-alerts.tf, the encryption-posture ledger, dsar-export.ts), not against the plan, the ADR or the PR description. One claim is FALSE against the code: PA-36 §(g)(8) says all three wrappers, the transport included, refuse while the cutover freeze sentinel is present; the transport wrapper reads no sentinel. That is the #4353/#4558 drift class (legal prose hallucinated against code) and it is the single condition. Everything else holds: no limb asserts a present-tense control on the unborn host; encryption at rest is stated NEGATIVE and matches the ledger's #6897 plaintext exception (expires 2026-10-22, disclosed_as not-publicly-claimed); the §(g)(3) correction is accurate; class-(ii) basis and the LIA are recorded OPEN (item 13), not asserted closed; no published document changes and none needs to. No Art. 33 and no Art. 34 duty arises."
blocking_findings: []
required_before_merge_DISCHARGED:
  - "C1 — PA-36 §(g)(8): replace the transport-freeze claim with the measured position (exact text under §Conditions). The ADR-149 review-pass row and the 2026-09-11 learning carry the same over-claim; those are engineering records outside this attestation's envelope and are flagged to the lead, not conditioned."
optional_precision_notes:
  - "O1 — The refusal text the wrappers print to stderr, and the execFile error message (`Command failed: ssh … git@<host> <workspace_id>`), both carry the raw workspace id, which equals `auth.users.id` for sole-owned workspaces. `reportSilentFallback` hashes `extra.userId` but the id also rides inside `err.message` into Sentry and the pino mirror. PA-36 §(g)(3) makes no hash-only claim for this event, so nothing recorded is false; the observation belongs with #8094 (Art. 5(1)(c) on the erasure-failure event), not in this PR."
  - "O2 — Header surface list: the sentence now reads `… (PA-34); and … (PA-35); and — declared, not live — …`, a doubled serial `and`. Style only."
  - "O3 — The provision wrapper does not `--one-file-system` anything (it creates); the erasure claim in §(g)(8) is correctly scoped to `rm`. No change."
attests:
  - knowledge-base/legal/article-30-register.md (PA-36 in full; PA-2 §(e) forced-command wording; PA-2 replication-row PA-36 cross-reference; header surface list; Hetzner vendor row `36 (declared, not live …)`; Register Maintenance item 13 — ONLY)
does_not_attest:
  - "knowledge-base/engineering/architecture/decisions/ADR-149-*.md review-pass row (engineering record; carries the same transport-freeze over-claim — see C1 note)"
  - "docs/legal/** and plugins/soleur/docs/pages/legal/** — untouched by the PR (verified `git diff origin/main...HEAD --stat` over both trees is empty), correctly so"
art_33_triggered: false
art_34_triggered: false
re_evaluation_triggers: "The host's birth (ADR-149 route completes) OR `GIT_DATA_STORE_ENABLED` flips OR the first repository is written to the store — at which point PA-36 §Status's three re-runs (the §(e) transfer check, the §(f) Hetzner-side backup-retention measurement, the class-(ii) LIA) are due and #8094 / #8101 must be closed or the published delete-account statements qualified. Also: first arms-length (non-Jikigai-affiliate) workspace owner, any EEA-out owner, any regulated-industry owner — the standing external-counsel triggers."
---

# Counsel review audit — #8043 / PR #8052 (PA-36, declared-not-live)

This file is the load-bearing evidence for the ship Phase 5.5 Counsel-Review CLO-Attestation Gate on PR #8052 (plan brand-survival threshold `single-user incident`). The register diff is the only legal artifact in the PR. The CLO agent is the v1 attestation authority; the operator holds an optional veto.

## Per-artifact verdict

| # | Artifact (register section) | Verdict | Verified against |
|---|---|---|---|
| P1 | Header — surface list gains the git-data store "declared, not live" | **APPROVED.** Tense carried explicitly; consistent with the #7331 re-key rationale. (O2 style note.) | register header |
| P2 | PA-2 §(e) — "git-shell-restricted key" → "forced-command-restricted key (see PA-36 §(g)(5))" | **APPROVED.** `cloud-init-git-data.yml` `users:` block sets `shell: /bin/sh`; the three `command=` lines in the `authorized_keys` write_files entry are the whole confinement; `git-data-bootstrap.sh` reads the shell back and refuses a restricted one. The old wording described a control that made every forced command exit 128. | cloud-init, bootstrap |
| P3 | PA-2 replication row — cross-reference to PA-36 | **APPROVED.** Division of record (transport + device encryption stay in PA-2; content/subjects/retention/erasure in PA-36) is coherent; PA-2 (g) verified to end at (21), so the "no (g)(22)" finding in PA-36's scope note is correct. | register PA-2 |
| P4 | PA-36 (a) Controller | **APPROVED.** Jikigai as controller per DPD §4.2(a); infrastructure limb (3). The alternative (owner-as-controller / Jikigai-as-processor for class (ii)) is recorded as an open counsel question, not decided — correct restraint. | DPD §4.2(a) |
| P5 | PA-36 (b) Purposes | **APPROVED.** "Sole durable copy of the delta" matches `git-data-replication.ts` module comment ("holds the SOLE copy of the delta between a user's last GitHub push and their worktree"). Future tense throughout. | git-data-replication.ts |
| P6 | PA-36 (c) subjects + categories; Art. 9/10 | **APPROVED.** Class (ii) involuntary subjects named honestly; workspace id = `auth.users.id` (mig 053 N2) recorded as a pseudonymous identifier; fence sidecar at `<id>.git/fence/` confirmed in `git-data-pre-receive.sh`. | pre-receive, replication.ts |
| P7 | PA-36 Lawful basis | **APPROVED.** Art. 6(1)(b) for the owner; for class (ii) the entry states 6(1)(b) does NOT reach them, names 6(1)(f) as a *candidate*, states an LIA is REQUIRED and none exists (verified: no file under `legitimate-interest-assessments/` covers it), and routes to item 13. Recorded OPEN, not asserted closed. Art. 22 negative determination appropriate for a passive object store. | LIA directory, item 13 |
| P8 | PA-36 (d) Recipients, (e) Transfers | **APPROVED.** Hetzner only, same AVV; `var.location` validation-pinned to `nbg1`/`fsn1`/`hel1` (`variables.tf`, #6453); boot telemetry to Sentry/Better Stack carries no repository bytes (ADR-198). No new sub-processor, no Chapter V transfer. | git-data.tf, variables.tf |
| P9 | PA-36 (f) Retention | **APPROVED.** Erasure path `account-delete.ts` step 3.01 → `removeGitDataRepo` → `git-data-remove.sh` `rm -rf --one-file-system` of the validated direct child; absent repo exits 0 (idempotent) — all verified. Plaintext residual cites the ledger row exactly (`does_not_defend` string, #6897, `expires_on: 2026-10-22`). Hetzner snapshot retention correctly flagged unmeasured. | remove.sh, account-delete.ts, ledger |
| P10 | PA-36 (g)(1) Encryption at rest — NEGATIVE | **APPROVED.** Stated as not-to-be-claimed; `REPO_ROOT` defaults to `/mnt/git-data/repositories` on the plaintext ext4 volume in all three wrappers and the bootstrap; ledger `disclosed_as: not-publicly-claimed`. Published docs claim LUKS ONLY for the serving host's `/workspaces` volume (privacy-policy "volume from which the Web Platform serves workspace git data", PA-2 (g)(21)); `docs/legal/**` contains zero occurrences of `git-data`. Matches. | wrappers, ledger, docs/legal |
| P11 | PA-36 (g)(2) erasure wrapper, dated | **APPROVED.** `mountpoint -q "$MOUNT_ROOT"`, fail-closed when `mountpoint(1)` absent, `-d` on the root, root-on-mount check via `stat -c %m`, no store create — all present in `git-data-remove.sh` and `git-data-provision.sh`. Date phrasing ("the date is the merge, not this line's authoring") is the correct way to date a not-yet-merged control. | remove.sh, provision.sh |
| P12 | PA-36 (g)(3) application-layer boundary — the review correction | **APPROVED.** `sshWithPrivateKeyAuth` is `promisify(execFile)` (git-auth.ts:30, :466); a non-zero remote exit rejects with an error carrying `stderr` and `code`, and Node's message embeds the stderr (`remote: git-data remove: …`). Step 3.01 catches, calls `reportSilentFallback` (`feature: "account-delete"`, `op: "git-data-bare-repo-erasure"`), which mirrors to pino and `Sentry.captureException(err)`, then continues. So a refusal IS distinguishable from a blip in Sentry/Better Stack; the user-facing outcome is not consulted (#8094, OPEN). `issue-alerts.tf` has no rule matching that `op` (0 hits). All three sub-claims true. (O1 note.) | git-auth.ts, account-delete.ts, observability.ts, issue-alerts.tf |
| P13 | PA-36 (g)(4)–(7) | **APPROVED.** (4) #8101 OPEN, states the mapper gap honestly. (5) three `tls_private_key` resources, Doppler `prd`, three-distinct-keys birth gate (#8035 merged), `/bin/sh` rationale measured. (6) `root:root 0644` map in `root:git 0750` dirs, `AuthorizedKeysFile .ssh/authorized_keys` in `01-hardening.conf`. (7) `$HOOKS_DIR` `root:git 0750`; transport execs `git -c "core.hooksPath=${HOOKS_DIR}"` (wrapper last line; test T11 pins it). | git-data.tf, cloud-init, bootstrap, transport wrapper |
| P14 | PA-36 (g)(8) path validation + review-pass controls | **APPROVED WITH C1.** Charset/dot/slash rejection, canonicalisation, direct-child assertion, mount + root-on-mount refusal in all three wrappers, `rm -rf --one-file-system` — verified. **The cutover-freeze clause is false for the transport wrapper**: `git-data-transport-wrapper.sh` contains no `cutover_freeze` read (grep: 0 hits; only `remove.sh`, `provision.sh` and `pre-receive.sh` carry it). During a freeze a push is refused by the root-owned `pre-receive` hook (reached through the (7) hooksPath pin), and a fetch is not refused at all. | transport wrapper, pre-receive.sh |
| P15 | PA-36 (g)(9)–(12), (h) DSAR, Status | **APPROVED.** `dsar-export.ts` walks `/workspaces/<userId>/*` and never connects to git-data (verified); the reaped-checkout-with-unpushed-commits gap is flagged unverified rather than asserted closed. DPD §10.3(b) and T&C §14.1b quotations byte-match (`data-protection-disclosure.md:479`, `terms-and-conditions.md:372`); dialog copy matches `delete-account-dialog.tsx:68`. "Not false today" is the correct characterisation: nothing exists to be un-deleted. Re-classification trigger is threefold (host exists AND flag on AND first repo written). | dsar-export.ts, docs/legal, dialog |
| P16 | Hetzner vendor row; Register Maintenance item 13 | **APPROVED.** Item 13 poses both characterisations as a counsel question and times the LIA before the cutover (the PA-32 lesson). | register |

## Findings

- **F1 (C1, in-PR).** §(g)(8) over-claims the freeze refusal for the transport wrapper — see P14. Ruled a correction rather than a block: the mis-stated control protects nothing today (host unborn), the two wrappers that mutate the store do honour the sentinel, and the push path is fenced by the hook. But a register line that a `grep` of the shipped file falsifies is exactly the class this gate exists to stop.
- **F2.** No published document must change. `docs/legal/**` and the Eleventy mirror are untouched in the diff; the store is unborn and no published surface claims it (the #6588 retraction removed the last such claim). The five `docs/legal/**` CI gates are therefore not engaged by this PR.
- **F3.** Cross-domain note for the lead (not a condition): ADR-149's review-pass row and `learnings/2026-09-11-the-gate-i-skipped-…md` both state `.cutover-freeze` is "honoured by all three" / "the transport wrapper … honours `.cutover-freeze`". Same over-claim; engineering owns those records.

## Conditions

**C1 — apply before merge.** In `knowledge-base/legal/article-30-register.md`, PA-36 §(g)(8), replace exactly:

> from PR #8052 all three wrappers, the transport included, also refuse unless the store is mounted and the repository root sits on it (the (2) assertion), refuse while the cutover freeze sentinel is present, and the erasure's `rm` does not cross a mount boundary (`--one-file-system`).

with:

> from PR #8052 all three wrappers, the transport included, also refuse unless the store is mounted and the repository root sits on it (the (2) assertion); the provision and erasure wrappers additionally refuse while the cutover freeze sentinel (`.cutover-freeze`) is present — the transport wrapper does NOT read that sentinel, so during the freeze a push is refused only by the root-owned `pre-receive` fence in (7), which does read it, and a fetch (`git-upload-pack`) is not refused at all; and the erasure's `rm` does not cross a mount boundary (`--one-file-system`).

No other text change is required. Optional O1–O3 are non-blocking.

## Disposition of C1 — 2026-09-11 (lead, same PR)

C1 was discharged by changing the **code**, not the register: commit `e7c28337d` adds the same
`GIT_DATA_CUTOVER_FREEZE` refusal to `git-data-transport-wrapper.sh` (ahead of any exec, both verbs;
`git-data-transport-wrapper.test.sh` T12, mutant RED 32/2), so the §(g)(8) sentence "all three wrappers …
refuse while the cutover freeze sentinel is present" is TRUE on the merged tree and the proposed
replacement text is not applied. The audit's verification line for the C1 fact inverts accordingly:
`grep -c cutover_freeze apps/web-platform/infra/git-data-transport-wrapper.sh` → 2. The same
correction makes the ADR-149 review-pass row and the 2026-09-11 learning (F3) accurate as written.
O2 (doubled serial "and" in the header surface list) applied in the same commit. O1 (raw
`auth.users.id` in the execFile `err.message` reaching Sentry) routed to #8094 as a comment.

## Verification commands (re-runnable from the worktree)

- `grep -c cutover_freeze apps/web-platform/infra/git-data-transport-wrapper.sh` → 2 after `e7c28337d` (was 0 — the C1 fact at audit time); same grep on `git-data-remove.sh` / `git-data-provision.sh` / `git-data-pre-receive.sh` → non-zero.
- `grep -n 'execFileAsync = promisify' apps/web-platform/server/git-auth.ts`; `sed -n 209,222p apps/web-platform/server/account-delete.ts`.
- `grep -c 'git-data-bare-repo-erasure' apps/web-platform/infra/sentry/issue-alerts.tf` → 0.
- `grep -ci 'git-data' docs/legal/*.md` → 0 on every file; `git diff origin/main...HEAD --stat -- docs/legal plugins/soleur/docs/pages/legal` → empty.
- `gh issue view 8094 8101 6897 --json state` → all OPEN on 2026-09-11.
