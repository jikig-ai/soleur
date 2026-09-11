# Tasks — feat-one-shot-8043-git-data-hash-bound-hardening

Plan: `knowledge-base/project/plans/2026-09-10-fix-git-data-hash-bound-hardening-batch-plan.md`

## Phase 0 — preconditions (no edits)
- [x] Baseline hash = 3a2392fb…4ce1725 (re-derived with `git_data_rung2_user_data_sha256`)
- [x] Byte budget: stored 13748 / cap 32768 (headroom 19020)
- [x] Ten suites green: birth-gate 118, bs-archive 30, remove 15, provision 14, transport 23, emit 59, strip-parity 15, tmpl-strip 5, c4 10, op-contract 5
- [ ] Rehearsal suite (docker) baseline green

## Unit A — F8 / Guard 1 (remove + provision mount assertion; mkdir deletion)
- [ ] RED: remove.test.sh — mounted store still erases (T-mount-ok, written FIRST); unmounted → named reject, rc≠0, REPO_ROOT still absent; provision.test.sh — unmounted → refuses, no repo written; floors raised
- [ ] GREEN: `GIT_DATA_MOUNT_ROOT` seam + `mountpoint` fail-closed resolution + reject in remove.sh and provision.sh; delete both `mkdir -p "$REPO_ROOT"`
- [ ] Guard 1 mutation rows 1–6, 9, 10 demonstrated RED; 7, 8 PASS

## Unit B — F7 / F9 / FR3 / Guard 3 (ownership)
- [ ] RED: birth-gate suite fixture + ownership arm expects `owner: root:root`; rehearsal-suite static rows over bootstrap literals (traversal model); S1 runtime rows (git appends → denied; mv .ssh → denied; traverses + writes REPO_ROOT)
- [ ] GREEN (same commit): template `owner: root:root` on authorized_keys (perms stay 0600? → 0644 per plan) + `AuthorizedKeysFile .ssh/authorized_keys` in 01-hardening.conf; bootstrap: delete `chown -R .ssh`, three targeted chown/chmod (home root:git 0750, .ssh root:git 0750, file root:root 0644), HOOKS_DIR root:git 0750 split from REPO_ROOT, `install -o root -g root` for pre-receive, stat readback post-conditions; birth-gate lib ownership arm flipped + rationale corrected
- [ ] Guard 3 mutation rows demonstrated

## Unit C — F11 / FR8–FR11b / Guard 2 (sshd stage + routing)
- [ ] RED: S1 programmable systemctl stub (rc=5 for `sshd`, rc=0 for `ssh`) → healthy run must emit nothing; drop-in assertion rows (contrary value → row names directive; without-password normalization; empty drop-in → both named; rc 126/127/255 → could-not-measure); op-contract set-equality (a)(b)(c) + floor
- [ ] GREEN: template — `systemctl restart ssh`, `sshd -T` BEFORE the action, literal-stage emit on `sshd_config_warn`, comment rewrite; issue-alerts.tf in-list += sshd_config_warn; op-contract WARNING_STAGES += sshd_config_warn, WARNING_EMITS_ROUTED_BY_FATAL_RULE=["gc_timer"], header rewritten
- [ ] Guard 2 mutation rows demonstrated

## Unit D — F6 / F10 (comments)
- [ ] variables.tf: `identity-shaped` → capability-divergence wording (FR1)
- [ ] five AcceptEnv comment sites corrected (FR7 grep = 0)

## Unit E — Guard 4 (evidence provenance)
- [ ] RED: birth-gate suite rows 1–10 over a throwaway repo (git-fixture-env.sh)
- [ ] GREEN: `git_data_rung2_bound_files` + `git_data_rung2_evidence_provenance_gate` in the lib; arm 1 inside `git_data_rung2_rehearsal_gate` (shallow → HOLD); arm 2 advisory step in infra-validation.yml; `fetch-depth: 0` on git-data-host-create checkout

## Unit F — FR13 / Guard 5 (`--table` in Mode 1)
- [ ] RED: archive suite — Mode-1 `--table`/`--table-s3` row printing `ok   mode 1: a --table flag is never silently discarded`; stderr+rc runner; exit 64 naming BS_TABLE
- [ ] GREEN: betterstack-query.sh pre-scan or loud refusal; runbook note

## Unit G — docs, register, deletion, hygiene
- [ ] FR12: delete `git-data-rung2-boot-evidence.env` (never edited)
- [ ] FR14: ADR-149 amendment
- [ ] FR15: git-data-birth.md F8 trap note → assertion note (banner untouched)
- [ ] FR16: Art. 30 entry (identify the PA; absence = finding)
- [ ] FR17: follow-up issues at stated severities; FR18 #8043 body; FR19 priority coherence
- [ ] NFR4 byte budget re-run; NFR1 new hash recorded; QG7 freshness step dormant

## Exit
- [ ] Touched-shard gate: scripts + webplat (+ registered infra suites)
- [ ] gdpr-gate single pass on cumulative diff
