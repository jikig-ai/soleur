---
title: "infra: Inngest on-host LUKS key-continuity probe (#9927 item 2)"
date: 2026-10-26
slug: inngest-luks-key-continuity-probe
branch: feat-one-shot-9927-key-continuity-probe
issue: 9927
closes: none (Ref #9927 only; items 1 and 3 to 8 of the tracker remain open)
type: feat
priority: p3
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# infra: Inngest on-host LUKS key-continuity probe (#9927 item 2)

## Enhancement Summary

**Deepened on:** 2026-10-26 (headless, bounded pass: the plan had already run a CTO ruling, a CPO sign-off, a re-ruling on the dead-man, a learnings search, a repo-research pass, a functional-overlap check and a five-seat plan-review panel, so the deepen pass ran the mechanical gates and the citation and negative-claim sweeps rather than a second full agent fan-out).
**Gates run mechanically:** 4.6 User-Brand Impact (present, `single-user incident`), 4.7 Observability (5 fields, no SSH, allowlisted verb `grep`, literal `expected_output`, `credentials_required` declared, command is not suite-shaped), 4.8 PAT-shaped variables (none), 4.9 UI wireframe (no UI surface; skipped), 4.10 Encryption Posture (present, `does_not_defend` non-empty, no exception block needed), 4.11 Guard Contract (`python3 scripts/lint-guard-contract.py` green, 3 entries), 4.12 Scope Check (one unfenced section, no `unmapped` row, descoped row justified, `Recommendation:` line present), 4.13 Task Design (not triggered: no new workflow, function, timer or daemon; the probe reuses the existing 30 s oneshot), 4.55 Downtime (not triggered: no replace, no lock-taking DDL; the probe adds at most about 100 s to one tick per day), 4.5 Network connectivity (not triggered: the plan addresses no connectivity symptom).
**Citation sweep:** every `knowledge-base/` path in the plan resolves; every cited issue and PR was read live (states in Premise Validation); every `hr-`/`wg-`/`cq-` rule id resolves (one is migrated-but-active, `wg-architecture-decision-is-a-plan-deliverable`); labels `follow-through`, `domain/engineering`, `priority/p3-low`, `type/chore` exist; every test and script path named exists on the branch (`scripts/regenerate-shard-manifest.py`, `plugins/soleur/test/workflow-file-size.test.ts`, `plugins/soleur/test/terraform-target-parity.test.ts`, the C4 suites, `run-registered-suites.sh`, the sibling alert suite).
**GDPR gate (advisory, triggered by the single-user-incident threshold):** the five v1 checks have nothing to match: no schema column, no PII table, no FK to `users`, no new non-EEA vendor or SDK (Better Stack ingest and the existing phone-home are reused), no Art. 9 column name. No findings. This is not legal review; the header-backup questions stay with the CLO under #9927 item 1.

### Key improvements found in the deepen pass

1. Verified the phone-home row shape from the source: the payload is `{message: "<marker> stage=<stage> <detail>", marker, stage, detail, host, dt, ...}`, so a message-anchored `position(JSONExtractString(raw,'message'),marker)=1` matches the phone-home channel, a `dt` column exists for the dead-man's window filter, and a detail key named `stage` would duplicate the prepended one (already fixed: `at=`).
2. Verify-the-negative sweep over the plan's negative claims: "`inngest-cutover-flip` is admitted in `vector.toml`" confirmed (three lists); "`GUARD_REV` is pinned" confirmed (`cutover-inngest-workflow.test.sh` asserts `EXPECTED_GUARD` equals `GUARD_REV`); "the member scripts are not `user_data` inputs" confirmed (`inngest-host.tf` embeds `infra-config-install.sh`, `cosign-trusted-root.json` and the image pin); "`apply-web-platform-infra.yml` is the only workflow that applies the alerts file" confirmed by the workflow census; one claim weakened: the plan no longer attributes the "older bundle overwrites the baked script" behaviour to an ADR-135 passage it could not re-find (reworded to the mechanism).
3. Post-edit self-audit: after the plan-review edits the plan was grepped for the renamed or dropped symbols: no `stage=` key remains in a row example, the persistent-`indeterminate` issue appears only as a dropped item, never as one to file, and the paging alert carries no 90,000 s window.
4. `tasks.md` and `decision-challenges.md` already carry the load-bearing corrections (rows D10 and D11, the two-issue follow-up set, the `at=` literal, the web-host push check); nothing further to propagate.

### New considerations discovered

- The real-tool measurements and the ERR-trap measurement are dated 2026-10-26 on a file container and bash 5.3; the work phase re-measures and cites commands, not figures.
- The dead-man's 30-day window and the sandbox claim remain the two unproven items; both have explicit gates and fallbacks in Phase 2.3 and Phase 3.2.

## Overview

Add a read-only probe on the dedicated Inngest scheduler host that asks cryptsetup whether the passphrase the host holds still unlocks the LUKS2 header of the volume behind `/mnt/data`, and report the answer as one `SOLEUR_INNGEST_LUKS_KEY_PROBE` row that Better Stack can read without any host login. Two Better Stack alerts come with it: one that pages on a failed verdict, and one self-arming dead-man that fires when a once-seen probe stops producing a measured verdict.

The brief asked for the probe to be baked into the image and added to the STAGED list in `cloud-init-inngest.yml` (the #8408 registry precedent). That route edits `user_data`, which force-replaces the sole scheduler, and the same brief forbids a `user_data` change in this PR. The research below settles the conflict: only an edit to one of the four existing signed-bundle members ships to a running dedicated host without a replace, and only `inngest-cutover-flip.sh` among them runs on a timer. So the probe is a bounded function inside that script (CTO ruling D1, mandatory isolation), delivered to the dedicated host by the signed config-refresh bundle (ADR-135). STAGED, `DEST_SPEC`, the image pin and `cloud-init-inngest.yml` are not touched.

Nothing in this plan applies anything to production by hand. Merging ships the script, the alerts and the docs through the existing merge-time automation (including the existing web-host push of the script, see "Delivery and owner holds"). Reaching the dedicated host needs a bundle build and a digest promotion afterwards; those are production acts held for the owner (decision D9), not steps of this PR.

Rulings: rows D1 to D11 in `knowledge-base/project/specs/feat-one-shot-9927-key-continuity-probe/decision-challenges.md` (technical rows ruled by the CTO agent on 2026-10-26; brand threshold with CPO sign-off `approved with conditions`, all five conditions carried below; plan-review dispositions in D10 and D11).

## Research Reconciliation - Spec vs. Codebase

| Claim in the brief / tracker / earlier plan | Reality (measured 2026-10-26 on `origin/main` 8a8b8e9990) | Plan response |
|---|---|---|
| Brief: add the probe "baked into the image and added to the STAGED list" | `STAGED="inngest-redis.conf ... cat-inngest-cutover-state.sh"` (`cloud-init-inngest.yml`, runcmd, first boot only) is rendered into `user_data`; `hcloud_server.inngest` carries no `ignore_changes = [user_data]` (only `ssh_keys`), so any edit force-replaces. A new baked file also needs an in-image install block that only a replace reaches (runbook `inngest-server.md`: the dedicated host's live flip is `inngest-host-replace`). | STAGED is NOT touched. Delivery is the signed bundle (D1). The brief's own hard constraint wins over its suggested mechanism. |
| Brief: "headroom is now about 800 B (host-config bundle)" | The 804 B is the Hetzner `user_data` cap headroom (`bash apps/web-platform/infra/inngest-userdata-budget.sh`: stored 31,964 B of 32,768 B, headroom 804 B). The config bundle has no byte cap (`inngest-config-bundle-pack.sh`, build workflow: no size check). A refresh-set member edit changes zero `user_data` bytes (`user_data` embeds `infra-config-install.sh`, `cosign-trusted-root.json` and the image pin via `file()`, `inngest-host.tf`; not the member scripts). | The headroom is irrelevant to the chosen route; record the figure before and after and leave it unspent. |
| Tracker #9927 item 2: "Needs cloud-init user_data, which force-replaces the sole scheduler" | True for a new script or unit (new `DEST_SPEC` row, HARD-1 bars units from the channel). Not true for an edit to an existing member whose `DEST_SPEC` row already exists on the host. | D1: ride an existing member. |
| Tracker: "Items 2 and 4 ride that replace" (dated trigger 2027-01-08 or the next planned replace) | The 2026-10-26 replace window passed without a keeper (the 2026-10-24 prework scoped PR-2, the keeper trio, and PR-D, the STAGED edit; neither was built; PR-1 was, `205e861082`). | The in-FSM probe gives detection now; a standalone keeper trio at the next replace stays a tracked follow-up (D8), with the in-FSM function deleted then. |
| Brief: "the host replace and bundle v5 promotion already happened on 2026-10-26" | No commit, runbook or ADR on `origin/main` records that window or a v5 promotion; the promoted pointer lives in Doppler (`soleur/prd_terraform`), not in the repo. Prep commits dated 2026-10-26 exist (#10966, #11139, pin bumps #11127 #11129 #11234). | Treated as the brief's statement; the plan makes no step depend on it except the delivery hold, which reads the applied bundle version from the latest `SOLEUR_INFRA_PULL_APPLIED` row before choosing the next version. |
| Brief: "use the key the host holds" | The key is on the host at `/etc/default/inngest-luks` (0600 root, one variable `INNGEST_REDIS_LUKS_KEY`), written at first boot and read by `inngest-luks-open.service` at every reboot. The registry precedent probes the Doppler-held key instead. | D2: probe the host file. The Doppler-overwrite mode already has a 12 h drift detector (ADR-282 table row "Doppler secret overwritten with another value"); the gap the probe fills is the row "LUKS header corrupted", whose detection lags to the first Redis failure. |
| Tracker: item 2 "precedent: registry-luks-escrow, #8408" | Precedent exists in `cloud-init-registry.yml` (`registry-luks-escrow.sh`), with a memory pre-check that sleeps and retries 3 x 300 s, and a `systemd-run --scope` OOM property that the real tool rejected (learning 2026-09-21). | Reuse the closed vocabulary, the `luksUUID` and `luksDump` pre-checks and the stdin key path; do NOT reuse the sleep-retry (it would stall the only control poll) or the scope property. |
| The flip script's header says "NINETEEN" seams; the seam-list comment says "sixteen names" | The `for _seam in` list has 19 names. | The same edit fixes the stale "sixteen" comment when adding the new seams (CTO B2). |
| Earlier plan and this brief: "no host fan-out" for a member edit | `inngest-cutover-flip.sh` is a `file()` hash input of `terraform_data.deploy_pipeline_fix` `triggers_replace` (`server.tf`, anchor `file("${path.module}/inngest-cutover-flip.sh")`) and is in `apply-deploy-pipeline-fix.yml` `paths:` (comment "a body-only edit must fire this apply"). Merging therefore fires that targeted apply: it pushes the web-host payload (webhook plus the tunnelled SSH bridge) to the web hosts, where the script is an inert file (no flip timer on web). | Stated in "Delivery and owner holds" and "Host fan-out"; post-merge AC checks `files_written == files_total`; the ship `DEPLOY_PIPELINE_FIX_TRIGGERS` gate applies; no `[skip-deploy-fix-apply]` marker (the web copy must stay in lockstep or the trigger lists diverge). Found at plan review (architecture and Kieran seats). |
| Sharp-edge claim (and CTO B3): "`|| true` on the call does not stop the ERR trap" | Measured on bash 5.3 under `set -Eeuo pipefail` with an ERR trap installed: `( probe ) \|\| true` suppresses both `errexit` and the trap inside the subshell (a failing `false` does not abort the body); a bare `( probe )` fires the trap and exits the script. | The `trap - ERR EXIT; set +eEx` disarm stays as defence in depth (a future call outside the `\|\| true` context), the wording is corrected, and the probe never relies on `set -e` (every step tests its own rc). The suite tests the disarm with the wrapper called outside an `\|\|` context. Found at plan review (Kieran seat). |
| Open PRs / worktrees | #10692 (open, unrelated) and #10936 (merged) are not touched. | Not touched. |

## Research Insights

### Premise Validation

Checked live: #9927 OPEN (items 1, 3 to 8 remain), #8408 CLOSED, #9879 CLOSED, #9786 CLOSED, #10966 MERGED, #10936 MERGED, #10692 OPEN draft, #10112 OPEN, #10390 OPEN, #8620 OPEN, #9060 OPEN (promotion is still manual), #10382 OPEN (not touched), PR #11260 is this draft. Cited paths all exist on `origin/main`. The mechanism check against the ADR corpus: ADR-282 row "On-host header backup or `luksOpen --test-passphrase` continuity probe | Deferred (#9927) | Both edit cloud-init `user_data`" is the record this plan narrows (the probe half no longer needs `user_data`); the header-backup half stays deferred and legal-gated. ADR-135 (signed refresh channel) is the in-place delivery record; `hr-prod-host-config-change-immutable-redeploy` forbids in-place edits outside cloud-init, and ADR-135's signed bundle is the sanctioned exception for the four members. Stale premises found and corrected above: the "headroom" label, the missing keeper, the unverified v5 claim, the no-fan-out claim.

### Property List

1. A row (daily while healthy, hourly otherwise) says whether the key the host holds unlocks the LUKS2 header of the device backing `/mnt/data` (no mapper is opened, nothing is written).
2. A failed verdict (`fail_passphrase`, `fail_header`, `fail_key_absent`) pages; an unmeasured verdict (`indeterminate`) never pages on its own.
3. (Moved to a follow-up PR by D12.) A probe that stops producing measured verdicts after it had produced them pages once (self-arming dead-man counting only `ok` or `fail_*` rows, so an `indeterminate`-only stream cannot read as health); before first delivery nothing pages.
4. Adding the probe cannot change the FSM's behaviour: the flag, the exit status and the FSM rows are byte-identical with or without it, even if every tool the probe calls hangs or fails.
5. The passphrase is never printed, put in argv, held in a shell variable, or written to any log, state file or marker.
6. The change reaches the dedicated host with no `user_data` change and no host replace.

### Cut List (mechanism, property, what already covers it)

- New keeper trio in STAGED: property 6 forbids it; the in-FSM function covers properties 1 to 5 now (D1). Tracked as a follow-up for the next replace.
- Doppler-side read of the key: overlaps the 12 h drift detector and widens the secret surface of the control script (D2).
- Both-legs comparison (host file vs Doppler hash): same overlap, plus an unverified token scope (D2).
- Header backup, Doppler repair route, token downgrade: not properties of this task; tracker items 1, 3, 4 stay open (D8).
- A `GUARD_REV` bump: serves no property and reds two suites (D7); the first probe row is its own delivery proof.
- A new Vector tag: `inngest-cutover-flip` is already admitted in `vector.toml` (three lists); a new tag would need an image bake and a pin bump.
- A kill-switch flag read by the probe: no no-SSH channel can set it (the unit's `--only-secrets` list is fixed). The rollback is a revert PR plus a higher-versioned bundle (see "Delivery and owner holds").
- A separate persistent-`indeterminate` signal: subsumed by the dead-man counting only measured verdicts (plan review, spec-flow P0-1).

### Institutional learnings applied

- `2026-09-21-my-escrow-suite-stubbed-the-one-tool-that-would-have-refused-it.md`: run the real `cryptsetup` once with the exact flags (done below, on a file-backed LUKS2 container, no root needed); stubs must drain stdin on `--key-file -`; use the `/proc/self/oom_score_adj` primitive, not a scope property.
- `test-failures/2026-09-30-stub-drain-fidelity-and-endpoint-keyed-sweeps.md`: the luksOpen stub must read stdin or `printf | cryptsetup` hits EPIPE under pipefail and forges a fake mismatch; add a wire assert on the key bytes.
- `2026-08-04-the-code-i-read-as-not-encrypted-was-a-default-errno-bucket-and-my-capture-forged-it.md` and `2026-09-20-my-probe-graded-itself-against-a-clock-its-grader-never-read.md`: rc 1 is a default bucket; forward the rc and a fixed literal in the row; map each rc to a verdict explicitly.
- `2026-07-15-self-healing-guard-on-a-blind-host-must-fail-safe-on-its-own-instrument.md`: absolute tool paths, tool-not-found is `indeterminate`, never a verdict about the key.
- `best-practices/2026-07-03-enforcement-probe-must-discriminate-exit-codes-not-any-failure-as-safe.md`: only rc 0 is positive, only rc 2 means "no keyslot unlocked".
- `2026-07-08-inngest-cutover-authoring-review-and-observability-allowlist.md`: the tag must be in `vector.toml` Source 4; `inngest-cutover-flip` already is.
- `test-failures/2026-10-06-which-files-feed-user-data-with-no-ignore-changes-decides-whether-a-mechanical-edit-is-a-host-replace.md`: the carrier checklist (resource lifecycle, `triggers_replace`, pin tests, sibling suites); applied in the Reconciliation table.
- `2026-07-16-a-drift-guard-can-recreate-its-own-bug-and-a-forced-replace-from-a-stale-pin-ships-nothing.md`: not engaged (no replace), but the bot pin-bump PR minted by a carrier edit is routine drift only.
- `2026-06-18-inngest-secrets-env-not-argv-and-detection-sentinel-swap.md`: key via stdin only; detection by a non-secret sentinel.
- Gap: no learning documents the ADR-135 refresh channel end to end; the runbook `inngest-config-refresh.md` and the engine's `good_members` gate (`^[A-Za-z0-9._-]+\.sh$`) are the sources.

### Measurements (2026-10-26, planner, offline)

- Budget: `bash apps/web-platform/infra/inngest-userdata-budget.sh` prints stored 31,964 B, cap 32,768 B, headroom 804 B (unchanged by this plan).
- Real `cryptsetup` 2.8.8 on a 20 MiB file-backed LUKS2 container with a synthesized key (no root, no device, `--pbkdf pbkdf2` for speed): `luksOpen --test-passphrase --disable-locks --key-file -` returned rc 0 for the right key, rc 2 ("No key available with this passphrase.") for a wrong key, rc 1 for empty stdin ("Nothing to read on input."), rc 4 for a missing device, rc 1 for a 4 MiB-zeroed header and for a blank device ("not a valid LUKS device"). A trailing newline on the key made the right key fail (rc 2), so the extraction must strip it. A first-8-KiB wipe did not break the open (LUKS2 keeps a redundant secondary header). The `sed -n 's/^INNGEST_REDIS_LUKS_KEY=//p' | head -n1 | tr -d '\n'` extraction piped into the call returned rc 0. The runs used a tiny pbkdf2 keyslot; the production keyslot is argon2id and its KDF memory is measured on the host by the `luksDump` pre-check.
- `errexit` and the ERR trap inside `( f ) || true` (bash 5.3, `set -Eeuo pipefail`, trap installed): suppressed, `false` does not abort the body; bare `( f )` fires the trap twice and exits. See the Reconciliation table.
- CLI verification (cq gate): `cryptsetup --help` on 2.8.8 lists `--test-passphrase`, `--disable-locks` ("Disable locking of on-disk metadata") and `-d, --key-file`. The host runs Ubuntu's packaged cryptsetup (older); both flags predate 2.0, but the work phase must run the call once against the pinned host package version in the rehearsal arm and record it.
- Host class: `inngest_server_type` defaults to `cpx22` (4 GB); redis `maxmemory 256mb`. An argon2id keyslot can ask for up to about 1 GiB, hence the `luksDump` memory pre-check.

## User-Brand Impact

- **If this lands broken, the user experiences:** the sole Inngest scheduler's 30-second control poll slows, stalls, or (through a mis-fired ERR trap) overwrites the production flag with `aborted`; one user's reminders, crons and agent runs stop firing or fire late, and the only no-SSH rollback channel is degraded.
- **If this leaks, the user's workflow is exposed via:** the LUKS passphrase of the store that is the sole copy of queued reminders reaching a log line, a marker, argv or a state file and from there the third-party log sink; the plan keeps the key on a stdin pipe only, forbids a variable, and adds a sentinel census over every output channel.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** the probe is read-only, but it edits the control script of the only scheduler and handles the store's passphrase; a stricter threshold is the conservative default (CTO, D6). CPO sign-off 2026-10-26 is `approved with conditions`: (1) a rollback path independent of the probe, (2) a test proving the flag is byte-identical on probe failure, (3) `indeterminate` does not page and a dead-man exists for a missing row, (4) documented dispatch, promotion and first-row verification steps, (5) a stated limit that no recovery exists if the header is lost, with the legal-gated backup issue linked. All five are acceptance criteria below. `soleur:engineering:review:user-impact-reviewer` runs at review time. The operator may lower the threshold; that is a taste call, not a technical one.

## Problem Statement / Motivation

ADR-282 records that if the LUKS header is damaged or a keyslot altered, "detection lags to the first Redis failure", and no recovery exists (header backup is deferred and legal-gated). The only opener the host reads is the key in `/etc/default/inngest-luks`, and nothing today proves it still unlocks the header between boots; the first proof is the next reboot, when a failure is also the loss. The registry host closed the same gap in #8408 with a daily `--test-passphrase` escrow check. The Inngest store is a sole copy, so the same continuity signal is owed here, and it has to arrive without a replace.

## Proposed Solution

### What changes

- `apps/web-platform/infra/inngest-cutover-flip.sh` gains one function, `luks_key_probe_tick`, called from exactly four places: the tail of the terminal-noop arms of `run_flip` (`done`, `rolled-back`, `aborted`, the `*)` unset arm), after each arm's own `emit_state`. It is never called from `armed`, `flipping`, `flushed`, `reflush` or `rollback`, and never from inside `emit_state` (which would break the reason-set-by-shape derivation in `cutover-inngest-workflow.test.sh`). The script's header invariant ("EVERY branch emits a JSON line") gets a stated exception for the probe row.
- `apps/web-platform/infra/betterstack-logs-alerts.tf` gains two `logtail_exploration` plus `logtail_exploration_alert` pairs.
- `.github/workflows/apply-web-platform-infra.yml` gains the matching `-target` lines (the dead-man pair only after the live probe in Phase 3).
- Docs: ADR-282 (row wording and addendum) with a one-line pointer in ADR-135, the runbook `inngest-luks-cutover-6894.md` section 5c, one C4 description edit.

### The probe (design, ruled)

Called as `( luks_key_probe_tick ) >/dev/null 2>&1 || true`. Inside the subshell, first statements: `trap - ERR EXIT; set +eEx; set +o pipefail`. Every external command is wrapped in `timeout -k 5 <n>` and addressed by absolute path or a seam name; every step tests its own rc. Flow:

1. Due check against the stamp `/var/lib/inngest-cutover/luks-key-probe.stamp` (the unit's `StateDirectory`, kept across reboots, lost on replace so a replaced host probes on its first tick). Due when the stamp is absent, or its token was `ok` and it is at least 24 h old, or its token was anything else and it is at least 1 h old. The stamp is written FIRST with a `pending` token (treated as non-ok) and rewritten with the verdict, so a probe that dies mid-run can never re-run every 30 seconds. If the `pending` write fails (read-only state directory, full disk) the probe SKIPS: an unrecordable stamp must never mean a KDF every 30 s.
2. Key: `grep -q '^INNGEST_REDIS_LUKS_KEY=.' /etc/default/inngest-luks` (tested without the value entering a variable); a missing, unreadable or empty value is `fail_key_absent` (at `key`). Assumption stated: the value is `random_password` with `special = false` (ADR-006 addendum), i.e. `[A-Za-z0-9]`, so raw `sed` and systemd's `EnvironmentFile` parsing (the reboot path) read the same bytes; the suite carries a case for a value with `=` and a trailing space, and the runbook records the assumption.
3. Device: `findmnt -no SOURCE -T /mnt/data | tail -n1` (under `ReadWritePaths=/mnt/data` systemd may bind-mount the path onto itself and print more than one line; the last is the kernel-served layer) must start with `/dev/mapper/`, else `indeterminate` (at `mount`); `cryptsetup status <mapper>` and its `device:` line, else `indeterminate` (at `status`). A missing `cryptsetup` binary or a `timeout` (124) is `indeterminate`, never a verdict about the key. The Phase 2.3 rehearsal asserts the real mountinfo shape under the unit's properties, not the seam.
4. Header: `cryptsetup luksUUID <dev>`: rc 0 with a value continues; rc 1 is `fail_header` only when `cryptsetup isLuks <dev>` also exits 1 (rc 1 is a default errno bucket, learning 2026-08-04; a second independent read must agree before a page); any other rc, including 4, 124, 126, 127, is `indeterminate` (at `uuid`). Residual stated: both reads share the default bucket, so a header fault and a permission fault inside the unit are not separable by exit code alone; the hourly re-probe and the runbook decision table cover it.
5. Memory: `cryptsetup luksDump <dev>` `Memory:` lines (largest, KiB; none means pbkdf2, 0); proceed only if `MemAvailable` is at least that plus 262144 KiB; otherwise `indeterminate` immediately (at `mem`). No sleep, no retry.
6. Shield: write `1000` to `/proc/self/oom_score_adj` inside the subshell (the cryptsetup child inherits it, the FSM process is never the victim); failure is `indeterminate` (at `shield`).
7. Proof: `sed -n 's/^INNGEST_REDIS_LUKS_KEY=//p' <keyfile> | head -n1 | tr -d '\n' | timeout -k 5 30 cryptsetup luksOpen --test-passphrase --disable-locks --key-file - <dev>`. The value never enters a variable, argv or a here-string. rc 0 is `ok`; rc 2 is `fail_passphrase`; anything else is `indeterminate` (at `kdf`). `--disable-locks` because under `ProtectSystem=strict` the `/run/cryptsetup` lock directory is read-only; the test only reads the header.
8. Emit one plain-text row `SOLEUR_INNGEST_LUKS_KEY_PROBE token=<tok> rc=<n> at=<literal>` twice: `logger -t inngest-cutover-flip` (already admitted in `vector.toml`) and the curl-direct `inngest-boot-phone-home.sh luks-key-probe "token=<tok> rc=<n> at=<literal>" SOLEUR_INNGEST_LUKS_KEY_PROBE`. The detail key is `at=`, not `stage=`: the phone-home builds its message as `<marker> stage=<arg> <detail>`, so a detail key named `stage` would duplicate it. The row is never JSON (the FSM-row counter in `cutover-inngest-workflow.test.sh` counts only rows whose message parses to an object), and carries no key, UUID, device id, hash or stderr (the phone-home redaction eats 32-plus hex runs).

Worst-case wall time is computed from the constants in the suite, not asserted: the command timeouts (the suite sums the literals in the script) plus a `-k 5` kill grace per site plus the logger and the phone-home `--max-time 8`, about 100 s, against `TimeoutStartSec=420`; at most once a day (hourly after a non-`ok` token) it delays the 30 s rollback poll by that much. In the `|| true` call context `errexit` and the ERR trap are suppressed inside the subshell, so the probe never relies on `set -e`; the disarm is defence in depth. New test seams (key path, stamp path, cryptsetup, findmnt, meminfo, oom-adj path) are added to the `for _seam in` list so they are honoured only under `--fixture-seams` (a Doppler-config name could otherwise redirect a root script).

### What the probe can and cannot claim (wording for the runbook and the ADR-282 row)

Can: at probe time, the key held on this host at `/etc/default/inngest-luks` unlocks a keyslot of the LUKS2 header on the device behind the `/mnt/data` mapper; this covers the reboot path (`inngest-luks-open.service`) for that device.
Cannot: that the Doppler copy equals the host file (the 12 h drift plan covers that; a host replace reads Doppler); that a header backup exists; that the header survives a future device fault; that the device behind the mapper is the by-id volume the boot unit opens (they coincide by construction while mounted; the probe does not derive the boot unit's device); or that a failed header is recoverable (ADR-282 "No recovery" stands until the legal-gated backup ships). A page means the key no longer opens the volume.

## Implementation Phases

### Phase 1 - Tests first (RED)

- 1.1 New suite `apps/web-platform/infra/inngest-luks-key-probe.test.sh`: sources `inngest-cutover-flip.sh` the way `inngest-cutover-flip.test.sh` does, drives every verdict through stubs for `findmnt`, `cryptsetup` (draining stdin on `--key-file -`, recording argv and the received key bytes), `logger`, phone-home and a `/proc/meminfo` fixture. Includes one real-tool arm against a file-backed LUKS2 container built in a temp dir (no root; skipped with an explicit marker, never silently, when `cryptsetup` is absent): right key rc 0, wrong key rc 2, blank file rc 1, trailing-newline key rc 2.
- 1.2 Guard 1 to 3 mutation rows written as failing cases before the function exists.
- 1.3 `apps/web-platform/test/infra/inngest-luks-key-probe-alert.test.sh` modelled on `inngest-luks-wrong-volume-alert.test.sh`: both alerts' SQL text and parameters, `token=fail_` present and `indeterminate` absent from the paging SQL, dead-man structure, `-target` parity. These are text-level assertions; the behaviour of the SQL is established by the read-only substitution runs in Phase 3.2.
- 1.4 Update `inngest-cutover-flip.test.sh` only where the seam-list derivation or counts demand it.

### Phase 2 - The probe (GREEN)

- 2.1 `luks_key_probe_tick` and its helpers in `inngest-cutover-flip.sh` per the design; four call sites; seams added to the `for _seam in` list; fix the stale "sixteen names" comment; amend the header invariant; one `local x=` per line (the command-position sweep in the existing suite derives suppressors from `(local )?NAME=` at line start). No `GUARD_REV` bump (D7).
- 2.2 Run `inngest-cutover-flip.test.sh`, the new suite, `inngest-carrier-vocabulary.test.sh` (no retired plaintext vocabulary in carriers), `doppler-injection-bound.test.sh`, `inngest-config-refresh.test.sh` (membership unchanged: still four), `cutover-inngest-workflow.test.sh`, `inngest-cutover-latch.test.sh`, the vector-admission and journald-config suites, and `python3 scripts/lint-encryption-posture.py` (the `--test-passphrase` site has one positional and is skipped by the mapper-less rule per `_luksopen_positionals`; confirm).
- 2.3 Rehearsal arm: run the function once under a transient unit with the flip service's sandbox properties (`ProtectSystem=strict`, `PrivateTmp`, `NoNewPrivileges`, `StateDirectory`, `ReadWritePaths=/var/lock /mnt/data`) against a loopback LUKS2 device, where root exists (CI), exercising the real `findmnt`, `cryptsetup status`, `--disable-locks` and the `oom_score_adj` write, and asserting the real mountinfo shape. Record the result in the PR and the runbook. If no root runner exists, the runbook carries an explicit `sandbox: unverified` line and the first-row verification (below) accepts only `token=ok`, so an `indeterminate at=mount|status|kdf` row is read as "not yet proven", never as delivery.

### Phase 3 - Alerts (Terraform, merge-apply route)

> **Superseded 2026-10-26 (D12):** 3.2 (the dead-man alert) and its `-target` lines are NOT built in this PR. No read-only call can prove the API accepts `query_period = 2592000`; the CTO ruled the dead-man ships in a follow-up PR after an owner-authorized create-and-delete probe, as a blocking prerequisite of the bundle promotion (#11266). The paragraphs below describe the follow-up's design.

- 3.1 Paging alert (mirrors `inngest_luks_wrong_volume`): `logtail_exploration.inngest_luks_key_probe_fail` plus `logtail_exploration_alert.inngest_luks_key_probe_fail`, SQL `position(JSONExtractString(raw,'message'),'SOLEUR_INNGEST_LUKS_KEY_PROBE')=1 AND position(JSONExtractString(raw,'message'),'token=fail_')>0`, `threshold`, `higher_than 0`, `check_period = 300`, `query_period = 10800`, `recovery_period = 3600`, `on_missing_data = treat_as_zero`, `paused = false`, email and escalation block mirrored from the sibling, `incident_cause` and `metadata.runbook` pointing at the runbook section. A non-`ok` probe re-runs hourly, so a failing probe keeps at least one row inside the 3 h window and a fixed one clears within about 3 h (a 25 h window would have held the incident open for a day). Presence-only, so safe before delivery.
- 3.2 Dead-man (mirrors the window mechanics of `luks_monitor_host_timer_dark`, which uses `lower_than 1`; this one is inverted to `higher_than 0` on a fire-flag): `inngest_luks_key_probe_dark` pair, one whole-window aggregate with no GROUP BY, arming on ANY marker row and counting recency only over measured verdicts: `SELECT toDateTime({{end_time}}) AS time, if(count(*) > 0 AND min(dt) < toDateTime({{end_time}}) - INTERVAL 26 HOUR AND countIf(dt >= toDateTime({{end_time}}) - INTERVAL 26 HOUR AND (position(JSONExtractString(raw,'message'),'token=ok') > 0 OR position(JSONExtractString(raw,'message'),'token=fail_') > 0)) = 0, 1, 0) AS value FROM {{source}} WHERE dt BETWEEN {{start_time}} AND {{end_time}} AND position(JSONExtractString(raw,'message'),'SOLEUR_INNGEST_LUKS_KEY_PROBE')=1`. `alert_type = threshold`, `operator = higher_than`, `value = 0`, `check_period = 3600`, `query_period = 2592000`, `recovery_period = 7200`, `on_missing_data = treat_as_zero`, `paused = false`; filter on the `dt` column never the `time` alias, never a `raw LIKE` prefilter (webhook payloads that quote the marker reach this source). Counting only `ok` and `fail_*` means a probe that emits `indeterminate` forever fires the dead-man after 26 h (this subsumes the earlier "persistent-indeterminate" follow-up), a failing probe keeps it quiet (the paging alert owns that), and nothing fires until the OLDEST marker row is 26 h old (CTO D10 amendment: arming on `count(*) > 0` alone would let a first `indeterminate` row, such as a transient low-memory skip before the first `ok`, fire the alert at the next hourly check). The read-only substitution controls must cover an indeterminate-first stream, an ok-first stream and an empty stream. This tightens the CTO's F4b SQL by restricting the recency count (plan-review P0 from three seats; recorded under D10).
  - Proof before the `-target` line (all read-only; no row is injected into the source): (a) the API accepts `query_period = 2592000` (fallback ladder: 604800, then a count variable defaulting to false, a second owner act); (b) run the aggregate through `scripts/betterstack-query.sh` with the marker swapped for a known live marker (for example the hourly `SOLEUR_INNGEST_SERVER_PROBE`): expect value 0 (alive); (c) with a marker that has no rows: expect value 0 (quiet before delivery); (d) with the recency window shortened to `INTERVAL 1 SECOND` on the live marker: expect value 1 (it can fire); (e) record query latency, and confirm the phone-home row's `message` begins with the marker (`position(...)=1` requires it) and lands in the same source, or count the logger channel only. If these cannot run in the work session, split the dead-man pair and its `-target` line into a second PR.
- 3.3 `apply-web-platform-infra.yml`: add the `-target` lines (paging pair now; dead-man pair after 3.2), check `workflow-file-size.test.ts` headroom (490,000 B gate). The merge plan must show exactly the alert creates plus the known standing drift, nothing else. Workflow census (`git grep -l -E "apps/web-platform/infra/\*\*|betterstack-logs-alerts" -- .github/workflows` on 2026-10-26): `apply-web-platform-infra.yml` is the only workflow that applies the alerts file; `infra-validation.yml` validates only; the scheduled drift job plans only. Re-run the census at work time and record the output (a second apply workflow reaching the resource would bypass the intended gate).

### Phase 4 - Docs and architecture

- 4.1 ADR-282: update the "Deferred (#9927)" row to say the probe half is merged by the in-FSM route (inert until delivered) and why, narrow the "LUKS header corrupted" detection cell, add a short dated addendum (isolation rules, accepted residuals, claim limits). One-line pointer in ADR-135's addendum that a refresh-set member may host a bounded periodic job under the ADR-282 isolation rules. No new ADR ordinal (an amendment); if review disagrees, `soleur:architecture create` with the ordinal re-verified across all pushed refs.
- 4.2 Runbook `inngest-luks-cutover-6894.md` section 5c, new subsection "Key-continuity probe (#9927 item 2)": token table and what each means; the claim limits; the key-charset assumption; a decision table for a page (see below); the dead-man's accepted residuals (bundle revert or older bundle, pipeline interruption over 26 h, self-disarm after 30 days of silence, never-promoted bundle) with "check the pipeline before the host" and a no-SSH diagnosis path (query the rows with `scripts/betterstack-query.sh`; compare the newest `SOLEUR_INFRA_PULL_APPLIED version=`); "a page means the key no longer opens the volume; header backup is the open, legal-gated item (#9927 item 1) and no recovery exists if the header is lost". `inngest-config-refresh.md`: one cross-reference line.
  - Decision table for a page (no SSH, no destructive step; every action that writes is owner-reserved): `fail_key_absent` (the next reboot cannot reopen the store) and `fail_passphrase` (header or keyslot no longer matches the host key): STOP, dispatch no host replace until the cause is established (a replace re-reads Doppler and may not open the volume); read the 12 h drift plan for the Doppler copy; the owner follows the existing "Per-loss-mode owner and procedure" table in this runbook (Doppler overwritten, state lost, header corrupted); `fail_header`: ADR-282 "No recovery"; follow "After a total loss" if the data is unreadable; open an incident with `soleur:incident`. `indeterminate`: read the `at=` literal; a dead-man page without a fail page means the probe cannot measure (`mount`, `status`, `mem`, `shield`, `kdf`): fix the measurement, do not treat as health.
- 4.3 C4: edit the `inngest -> betterstack` edge text and the `inngestRedis` description in `model.c4` to name the new marker and the narrowed detection claim; run the C4 suites.

### Phase 5 - Follow-up issues (deferral tracking, `Ref` only)

See "Follow-up issues to file". Filed at the start of the work phase.

## Delivery and owner holds

<!-- lint-infra-ignore start: describes held production acts and their verification; the PR performs none of them -->
**What the merge does by itself (automation, no operator step):**

- `apply-web-platform-infra.yml` creates the alert resources.
- `apply-deploy-pipeline-fix.yml` fires: `inngest-cutover-flip.sh` is a `triggers_replace` hash input of `terraform_data.deploy_pipeline_fix` and is in that workflow's `paths:`. It pushes the web-host payload (webhook plus the tunnelled SSH bridge) to the web hosts, where the script is an inert file (no flip timer on web). Expect `files_written == files_total` in the run, the ship skill's `DEPLOY_PIPELINE_FIX_TRIGGERS` gate applies, and no `[skip-deploy-fix-apply]` marker is used (the web copy must stay in lockstep with the trigger lists). The web-redeploy notice (#9755 text) goes in the PR body.
- `mint-inngest-bootstrap-tag.yml` mints a `vinngest` tag because `inngest-cutover-flip.sh` is a `cp`-staged carrier, and the bot opens a pin-bump PR that edits `cloud-init-inngest.yml`. That bump is routine: merge-apply `-target` lists exclude `hcloud_server.*`, so it shows only as standing drift (#10835, #10768) and replaces nothing. It is a separate PR from this one; this PR's diff contains no `user_data` change.

**What reaches the dedicated host only after the owner acts (held; production-mutating; decision D9):**

1. Pre-promotion checks (agent-runnable, read-only, recorded on the tracker): `bash -n` and a `--fixture-seams` smoke run of the script as packed into the built bundle; the Phase 2.3 rehearsal result; a review of the member diff since the last promoted bundle (the bundle is built from the default branch, so any other member edit merged since then ships too); an unmerged revert branch restoring the previous script, with `bash -n` and the `--fixture-seams` smoke green on it (a bundle the host will accept can only come from the default branch, so a probe-free bundle cannot exist before the revert merges; D13).
2. Dispatch `build-inngest-config-bundle.yml` from the default branch at a version above the applied one (read it from the newest `SOLEUR_INFRA_PULL_APPLIED version=` row; if that row is absent or past retention, read the drift comparator summary; the brief says v5, so expect 6), approved in the `inngest-config-signing` environment.
3. Promote the digest (`INNGEST_CONFIG_DIGEST` in `soleur/prd_terraform`, then the targeted apply per `inngest-config-refresh.md` step 3; #9060 automation is still open). A menu answer is not authorization for either step (`hr-menu-option-ack-not-prod-write-auth`). The plan builds none of it and dispatches nothing.
4. Before ANY future host replace, promote a probe-carrying bundle: a replaced host applies the currently promoted bundle over the image-baked script, so a promoted bundle that predates the probe silently drops it (the refresh engine installs whatever the promoted pointer names; ADR-135 records the floor and pointer behaviour).

**First-row verification (read-only, no SSH; also the close condition of the owner-hold tracker):** `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 2h --grep SOLEUR_INNGEST_LUKS_KEY_PROBE --limit 5`, read by meaning: a row from the SYSLOG_IDENTIFIER `inngest-cutover-flip` channel AND a phone-home row, both `token=ok rc=0`, within about two minutes of the next applied bundle (the 60 s refresh timer, then the first 30 s tick with no stamp). A webhook payload that quotes the marker, or an `indeterminate` row, does not satisfy it. `token=fail_*` pages. The first `ok` row is also the delivery proof (no `GUARD_REV` bump).

**Rollback (independent of the probe path, CPO condition 1):** a revert PR restoring the previous script, a new bundle built from the default branch at a higher version after the revert merges (hours; two owner acts, D13), and the same promotion. The refresh engine and units are not members, so the rollback path does not run through the probe. Expected side effect: the dead-man fires about 26 h after the measured rows stop (named in its `incident_cause`). A script that breaks every tick would kill the only no-SSH rollback channel on the dedicated host; that is why step 1 exists and why the isolation rules and the byte-identical-flag case are acceptance criteria.

**Residuals stated, not hidden:** if the bundle is never promoted, the dead-man stays quiet forever (the owner hold tracks delivery, not the alert; the tracker carries a due date); the dead-man self-disarms after 30 days with no rows at all (if the probe is ever dark that long, convert to the count-variable form; recorded on the keeper follow-up); the bot pin-bump PR is merged or closed per the existing image-release runbook, its standing drift is harmless.
<!-- lint-infra-ignore end -->

## Infrastructure (IaC)

### Terraform changes

`apps/web-platform/infra/betterstack-logs-alerts.tf`: two `logtail_exploration` and two `logtail_exploration_alert` resources, provider and pins unchanged (`logtail` already in the root), tier gating via `var.betterstack_paid_tier` exactly as `inngest_luks_wrong_volume`. No sensitive variable, no `doppler_secret`, no `random_*`, no new secret name (so the boot identity regex in `cloud-init-inngest.yml` is untouched).

### Apply path

Alerts: the existing merge-time automation (`apply-web-platform-infra.yml`, `-target` list), expected plan = the alert creates only, no skip marker. Web-host copy of the script: `apply-deploy-pipeline-fix.yml` (existing, described above). Dedicated-host script: the signed config-refresh bundle (ADR-135), the sanctioned in-place exception to `hr-prod-host-config-change-immutable-redeploy` for the four members, cosign-verified and monotonic-versioned; no SSH, no replace, no `user_data` change, no downtime (the probe runs inside an existing oneshot; worst-case added latency about 100 s at most once a day). Blast radius while delivered: the one scheduler host's control poll (bounded by the isolation rules).

### Host fan-out

No `terraform_data` SSH provisioner is added or edited. The existing `terraform_data.deploy_pipeline_fix` (and its web-2 sibling) re-fires because the script is one of its `triggers_replace` hash inputs; fleet classification: web hosts receive an inert copy, the dedicated Inngest host is untouched by that apply (it is a single host reached only by the bundle). No host is replaced.

### Distinctness / drift safeguards

No `dev != prd` surface. The refresh-set stays exactly four (`inngest-config-refresh.test.sh` S7 is the pin; no member added). `inngest-userdata-budget.sh` stays at 804 B because no `user_data` byte changes (record before and after in the PR).

### Vendor-tier reality check

Better Stack: the paid-tier gate on `escalation_target` mirrors the sibling. The 30-day `query_period` has no precedent in the file (longest is 97,200 s) and the provider does not validate it client-side; a rejection would fail the infra apply, which is why Phase 3.2 proves it before the `-target` line lands.

## Observability

> **Superseded in part by D12 and the 2026-10-26 review rulings (D13 to D17):** the dead-man alert is NOT in this PR (it follows an owner-authorized proof that Better Stack accepts `query_period = 2592000`, and is a blocking prerequisite of the bundle promotion, #11266). Wherever this section names the dead-man as shipped, read it as follow-up. Until it lands, probe silence, a persistent `indeterminate` and a mid-run death are detected only by the first-row verification and the `at=died` row; the alert route for those modes is none.

```yaml
liveness_signal:
  what: "SOLEUR_INNGEST_LUKS_KEY_PROBE row (token=ok|fail_passphrase|fail_header|fail_key_absent|indeterminate, rc, at) under SyslogIdentifier inngest-cutover-flip via Vector, and a curl-direct phone-home copy"
  cadence: "first 30 s tick after delivery (no stamp), then every 24 h after an ok, every hour after any other token"
  alert_target: "Better Stack logtail_exploration_alert on token=fail_ (pages), and a self-arming dead-man on a once-seen probe that has produced no ok or fail_ row for 26 h, both on the existing operator email policy"
  configured_in: "apps/web-platform/infra/inngest-cutover-flip.sh and apps/web-platform/infra/betterstack-logs-alerts.tf"
error_reporting:
  destination: "Better Stack Logs (layer 3, Vector journald shipper, source soleur-inngest-vector-prd) plus the curl-direct phone-home channel, independent of Vector at the credential level"
  fail_loud: "the probe never changes the tick's exit status (isolation rule); fail_* verdicts page via the alert; indeterminate emits a row with an at= literal and does not page on its own, the dead-man pages when no measured verdict arrives for 26 h"
failure_modes:
  - mode: "the host key no longer unlocks the header (altered keyslot, wrong volume, header damage)"
    detection: "layer 3: row token=fail_passphrase or fail_header; Better Stack exploration alert"
    alert_route: "operator email via the Better Stack policy"
  - mode: "the host key file is missing or empty (next reboot cannot reopen the store)"
    detection: "layer 3: row token=fail_key_absent at=key; Better Stack exploration alert"
    alert_route: "operator email via the Better Stack policy"
  - mode: "the probe could not measure (not mounted on a mapper, tool absent, timeout, low memory, shield refused)"
    detection: "layer 3: row token=indeterminate with an at= literal; never paged on its own (a transient would page a day); a persistent stream with no ok or fail_ row for 26 h trips the dead-man"
    alert_route: "operator email via the Better Stack policy (dead-man)"
  - mode: "the probe goes silent after it had spoken (bundle reverted or older, Vector or sink unavailability, probe code dead, host replaced and not yet probed)"
    detection: "layer 3: self-arming dead-man, quiet before the first row, fires after 26 h without a measured verdict"
    alert_route: "operator email via the Better Stack policy; the incident cause names a bundle revert and a pipeline interruption as expected causes"
  - mode: "the probe harms the control script (stray non-zero, hang, OOM)"
    detection: "layer 6 (workflow-run log of the required infra-validation suite): the isolation cases and the flag-byte-identical case fail before merge; at runtime the existing FSM rows and the 30 s liveness heartbeat (G3.7) would stop, read through the existing no-SSH operator gate"
    alert_route: "required check fails the PR; the existing cutover liveness alarms at runtime"
logs:
  where: "Better Stack source soleur-inngest-vector-prd (SYSLOG_IDENTIFIER inngest-cutover-flip); journald on the host is not a read path"
  retention: "90 days (betterstack-log-query.md, measured 2026-09-04); the dead-man's 30-day window sits inside it"
discoverability_test:
  command: grep -l SOLEUR_INNGEST_LUKS_KEY_PROBE apps/web-platform/infra/inngest-cutover-flip.sh apps/web-platform/infra/betterstack-logs-alerts.tf
  expected_output: inngest-cutover-flip.sh
  credentials_required: "Better Stack ClickHouse read connection (Doppler soleur/prd_terraform BETTERSTACK_QUERY_*) - there is no unauthenticated substitute for reading a host-emitted row; the property-level check is the first-row read in 'Delivery and owner holds'"
```

(The local probe prints both file paths because the marker is named in the script and in the alert file; it proves, without credentials or SSH, that the script emits the marker and the alert file names it. The credential-gated read of the live row is declared under `credentials_required` and is part of the post-delivery verification, per `hr-no-dashboard-eyeball-pull-data-yourself`.)

## Encryption Posture

```yaml
at_rest:
  - store: hcloud_volume.inngest_redis_luks (existing; this plan adds no store)
    mechanism: luks
    evidence: "scripts/encryption-posture-ledger.json row for the volume (mechanism luks, unchanged); live opener inngest-luks-open.service"
    defends_against: "physical or snapshot access to the volume without the passphrase; this plan adds a continuity signal that the host-held key still unlocks the header"
    does_not_defend: "loss of the header or of every passphrase copy (Art. 32(1)(c) NOT provided: no header backup exists, item 1 of #9927 stays deferred and legal-gated); a holder of the host root or the Doppler boot token reading the key; the probe is detection, not recovery"
    disclosed_as: not-publicly-claimed
    live_verification: "the first SOLEUR_INNGEST_LUKS_KEY_PROBE token=ok row is the first measured proof that the host key opens the header; unavailable until the bundle is delivered"
in_transit:
  - connection: "dedicated Inngest host -> Better Stack ingest (curl-direct phone-home, existing channel reused for one new marker)"
    enforced_at: "apps/web-platform/infra/cloud-init-inngest.yml inngest-boot-phone-home.sh (existing)"
    tls: "https, TLS 1.2+"
    cert_verification: on
    does_not_defend: "a compromised host reading its own phone-home token; the row carries no key, UUID or hash by construction"
    disclosed_as: not-publicly-claimed
```

## Guard Contract

### Guard 1 - the probe cannot change the FSM

**Property.** Whatever the probe's tools do (hang, error, vanish, return non-zero), the tick's exit status, the flag value and the FSM's own state rows are byte-identical to a run without the probe, and the probe is reachable only from the four terminal-noop arms.

**Assembly.** Chokepoint: the single wrapper `luks_key_probe_tick`, invoked only as `( luks_key_probe_tick ) >/dev/null 2>&1 || true`. Members that drift: the call sites in `run_flip`, the helpers it calls, every external command inside (each under `timeout -k 5`), the disarm. The suite derives the call-site set from the script by shape (every occurrence of the wrapper name) and asserts set equality with the four arms, and asserts none inside `emit_state`, `flag_set`, `run_preflush_flip` or the flush arms; it also enumerates every external command in the function body and asserts each is under `timeout` or is a shell builtin.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add a call to the wrapper inside the `armed` arm | RED (call-site set differs) |
| 2 | Delete `trap - ERR EXIT; set +eEx` from the subshell and call the wrapper OUTSIDE an `\|\|` context while a `cryptsetup` stub exits 1 | RED (the `flag_set` recorder fires, flag changes); the same deletion under the production `\|\| true` context stays green, which is why the disarm is tested outside it |
| 3 | Make the `cryptsetup` stub hang and remove the `timeout` from the KDF call | RED (tick exceeds the bound) |
| 4 | Add a second call site inside `emit_state` after a compliant first | RED (set equality and the `emit_state` exclusion) |
| 5 | Remove the outer `\|\| true` and make the wrapper `return 1` | RED (tick exit status changes) |
| 6 | Stub `cryptsetup`, `findmnt` and `logger` absent (127) | PASS only as `indeterminate`, flag and rows unchanged (compliant path not over-blocked) |
| 7 | Make the pending-stamp write fail (read-only state dir) | the probe SKIPS: no `cryptsetup` call, no row (a missing skip is RED) |

**Harness rows.** RED: make the suite's `flag_set` recorder a no-op; the suite must fail on its own recorder self-test (a recorder that cannot record proves nothing). Must-PASS non-canonical: a run where the stamp says not due (probe skipped), and a run where the noop throttle suppresses `emit_state`; both must leave the same flag and rows. **Anchor.** The expected call-site set lives in the suite beside the script, so one diff can edit both: consistency, not integrity; the outside anchor is the CODEOWNERS-routed review of `inngest-cutover-flip.sh` and the existing derivation tripwire in `inngest-cutover-flip.test.sh`.

### Guard 2 - the passphrase never leaves the pipe

**Property.** The key reaches `cryptsetup` only on stdin from a pipe: never in argv, a shell variable, a here-string, a log line, a marker, a state file, stderr, or the environment of any child.

**Assembly.** Every read of the key file (one `grep -q` presence test and one `sed` extraction site), the single `cryptsetup luksOpen --test-passphrase ... --key-file -` call, every emit site (the `logger` row, the phone-home row, the stamp write), and the xtrace refusal. The suite feeds a synthesized sentinel key and greps every captured channel (logger trace, phone-home trace, stamp content, stub argv log, stub environment dump, stderr) for the sentinel, and statically asserts no assignment from the key extraction and exactly one `cryptsetup` call carrying `--key-file -`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Replace the pipe with `key=$(sed ...)` then `printf '%s' "$key" \| cryptsetup ...` | RED (static: assignment from the key read) |
| 2 | Pass the key as `--key-file=<tmpfile>` or argv | RED (stub argv log contains the sentinel or the call lacks `--key-file -`) |
| 3 | Add a debug `logger` of the extracted value | RED (sentinel in the logger trace) |
| 4 | Add a second `cryptsetup` call (a "retry") without `--key-file -` | RED (call census) |
| 5 | Run the function under `set -x` | RED (the probe sets `set +x` and the suite asserts the trace holds no sentinel) |
| 6 | Strip `tr -d '\n'` from the extraction | RED (the real-tool arm: right key returns rc 2) |

**Harness rows.** RED: change the fixture key so the sentinel never reaches the stub; the wire assert (the stub's received stdin bytes equal the sentinel) must fail. Must-PASS non-canonical: a key with an `=`, a key file with a second unrelated variable and a trailing comment line (only the first match used), and a value with a trailing space (documented as outside the assumed charset: the suite pins the observed behaviour). **Anchor.** Local proof only; the live property is the first `token=ok` row and the absence of the sentinel class in Better Stack (no stored value to weaken).

### Guard 3 - seam gate and closed vocabulary

**Property.** The probe's new test seams are honoured only under `--fixture-seams`, and the probe emits only tokens from the closed set, which the alert SQL, the runbook table and the suite all enumerate identically.

**Assembly.** The `for _seam in` list in the script versus every `${CUTOVER_*}` / `${INNGEST_*}` read in the probe (derived by shape); the token set in the script versus the paging alert's SQL (`token=fail_` only), the dead-man's `ok` / `fail_` recency terms and marker match, the runbook table and the suite's verdict cases; the `-target` lines versus the alert resources.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Read a new seam in the probe without adding it to the `for _seam in` list | RED (the existing shape tripwire) |
| 2 | Honour a seam env var without `--fixture-seams` (delete one `unset` effect) | RED (extended refusal case over the new names) |
| 3 | Emit a token outside the closed set | RED (suite enumeration and runbook table parity) |
| 4 | Change the paging SQL to match `indeterminate` or drop `token=fail_` | RED (alert test) |
| 5 | Add the dead-man alert resource without its `-target` line, or the reverse | RED (target parity) |
| 6 | Change the dead-man recency terms to count `indeterminate`, or add a second marker spelling after a compliant first | RED (alert test: exactly one marker literal anchored with `position(...)=1`, recency terms exactly `token=ok` and `token=fail_`) |

**Harness rows.** RED: rename the sentinel marker in the alert test; the suite must fail. Must-PASS non-canonical: a phone-home-shaped row (`marker + " stage=..."`) and a logger-shaped row both count; a webhook-shaped JSON object quoting the marker must NOT. **Anchor.** The `-target` list is edited in the same diff as the resources; the outside anchor is `plugins/soleur/test/terraform-target-parity.test.ts` plus CODEOWNERS review of the workflow file.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-282 (Phase 4.1): the "On-host header backup or `luksOpen --test-passphrase` continuity probe | Deferred (#9927)" row is split, the probe half is marked delivered by the signed-bundle route with the reason ("an existing refresh-set member runs on an existing timer; no `user_data` bytes"), the "LUKS header corrupted" detection cell is narrowed, and a short dated addendum records the isolation rules (disarmed ERR trap, bounded tools, no retry, text-only row, seams behind `--fixture-seams`) and the accepted residuals; ADR-135's addendum gains a one-line pointer (an FSM-host periodic job is a convention beyond ADR-100's scope, so the pointer keeps both records honest). The CTO suggested a new ADR for the "in-FSM probe convention"; the plan treats it as an amendment because the decision is narrow, reversible, and scheduled to move to a standalone keeper unit at the next replace. If review prefers a new record: `soleur:architecture create`, ordinal re-verified across all pushed refs (highest on `origin/main` today: 303) and after any sync.

### C4 views

All three model files read (`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`). Enumeration: external human actor (the founder/owner receives the alert; already modelled), external systems (Better Stack, Doppler; already modelled), container `inngestRedis` (its description names the key as the only opener and the missing header backup; the detection sentence needs the probe), actor-surface access relationships (none change), data stores (none new). Relationship `inngest -> betterstack` already exists and lists shipped markers; the new marker is added to its prose. No new element, edge or `view include`. Tasks: edit those two descriptions; run `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts` and `plugins/soleur/test/c4-count-parity.test.sh` (edge prose may embed derived counts).

### Sequencing

The ADR amendment describes the delivered-and-gated target state; the delivery hold is stated in it. Nothing is postponed to a follow-up issue.

## Domain Review

**Domains relevant:** Engineering, Product (CPO sign-off for the single-user-incident threshold), Operations (owner delivery holds)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Ruled D1 to D8 on 2026-10-26 (vehicle A with mandatory isolation; host-file key; `--disable-locks` and bounded tools; marker, alert and the self-arming dead-man; threshold `single-user incident`; no `GUARD_REV` bump). Blocking facts folded in: ADR-282 already has a 12 h detector for a Doppler overwrite (B1); new seams must join the `for _seam in` list (B2); a carrier edit mints a tag and a bot pin-bump PR (B5); new alerts need `-target` lines (B6). Corrected by plan review: B3 (the ERR trap is already suppressed in the `|| true` context; the disarm is defence in depth).

### Product (CPO)

**Status:** reviewed
**Assessment:** Sign-off `approved with conditions` (five, listed in User-Brand Impact and carried as acceptance criteria). The failure modes that matter to one user are the flag overwrite, a stalled poll and a mis-fired page; the false-`ok` risk is bounded by the stated claim limits.

### Operations

**Status:** reviewed (planner)
**Assessment:** No vendor signup, no cost line. The only owner acts are the bundle dispatch and digest promotion (D9), documented with pre-promotion checks, exact steps, rollback and first-row verification.

### Legal (CLO)

Not relevant: no personal-data processing, no new store, no new recipient; the header backup and any Art. 17 or disclosure wording stay with the CLO under #9927 item 1 and are not decided here. `soleur:gdpr-gate` ran advisory-only on this plan at deepen time (the single-user-incident threshold triggers it): no findings (see the Enhancement Summary).

### Product/UX Gate

**Tier:** none - no UI surface file in Files to Create or Edit (no `components/**`, `app/**`).
**Decision:** N/A. **Pencil available:** N/A (no UI surface).

### Plan review (2026-10-26, five-seat panel at the single-user-incident threshold)

DHH, Kieran, code-simplicity, architecture-strategist and spec-flow ran. The named CEO/design/devex panel was not spawned again: the CTO and CPO had already ruled and signed off on the design in this session. Dispositions are in decision-challenges rows D10 (adopted mechanical fixes) and D11 (simplification proposals not adopted, with the ruling that stands).

## Open Code-Review Overlap

None. Checked the open `code-review` issues against `inngest-cutover-flip.sh`, its suite, `betterstack-logs-alerts.tf`, `vector.toml`, the runbook and the refresh-set file: no match.

## Files to Edit

- `apps/web-platform/infra/inngest-cutover-flip.sh` (probe function, four call sites, new seams in the `for _seam in` list, stale comment count, header invariant exception)
- `apps/web-platform/infra/inngest-cutover-flip.test.sh` (only where the seam derivation demands)
- `apps/web-platform/infra/betterstack-logs-alerts.tf` (two alert pairs)
- `.github/workflows/apply-web-platform-infra.yml` (`-target` lines)
- `knowledge-base/engineering/architecture/decisions/ADR-282-sole-copy-luks-volume-protection-set.md`, and the ADR-135 file (one-line pointer; derive its path with `git ls-files | grep ADR-135`)
- `knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md` (section 5c), `inngest-config-refresh.md` (one cross-reference)
- `knowledge-base/engineering/architecture/diagrams/model.c4`
- Registries (verify each is required before editing; derive with `git grep`): `apps/web-platform/infra/suite-shard-legs.tsv`, `apps/web-platform/infra/suite-durations.tsv` (`python3 scripts/regenerate-shard-manifest.py --group infra --incremental --write`), `scripts/lib/test-affected-paths.sh` (`AFFECTED_PLUGINS_SOLEUR_PATHS`), `scripts/ci-pr-affected-audit.baseline.tsv`, `.claude/hooks/grep-q-pipe-guard.test.sh` (pipe-pair table; the new `printf | cryptsetup` pipe site)
- Not edited, but its hash input changes: `apps/web-platform/infra/server.tf` (`terraform_data.deploy_pipeline_fix` `triggers_replace` hashes the script; no edit to that file).

## Files to Create

- `apps/web-platform/infra/inngest-luks-key-probe.test.sh` (auto-discovered by `run-registered-suites.sh`)
- `apps/web-platform/test/infra/inngest-luks-key-probe-alert.test.sh`

## Follow-up issues to file (deferral tracking; milestone from `knowledge-base/product/roadmap.md`, default Post-MVP / Later; `Ref #9927`)

1. Standalone `inngest-luks-keeper.{sh,service,timer}` in STAGED at the next planned host replace (trigger: that replace or 2027-01-08, whichever is first), deleting the in-FSM function; this is the future state that flips the threshold to `aggregate pattern`. The issue also records the dead-man trigger: if the probe is ever dark for more than 30 days (the self-disarm residual), convert the dead-man to the count-variable form.
2. Owner-hold tracker for the bundle build and digest promotion that delivers this probe (label `follow-through`, a due date, the first-row verification as its close condition), so the PR-ready gate sees a deferred operator step and not an undeferred one (`wg-block-pr-ready-on-undeferred-operator-steps`).
Not filed here (already carried by #9927 with its dated trigger): the LUKS header off-host backup (CLO-gated), the Doppler repair route, the host token downgrade. Dropped after plan review: a separate persistent-`indeterminate` issue (subsumed by the dead-man) and a separate permanent dead-man issue (folded into issue 1).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Implement #9927 item 2, the on-host LUKS key-continuity probe." [brief] | Phases 1 to 4 | mapped |
| 2 | "Add a probe that runs `cryptsetup luksOpen --test-passphrase` against the Inngest data volume using the key the host holds" [brief] | Phase 2.1 (`luks_key_probe_tick`), design steps 2 to 7 | mapped |
| 3 | "baked into the image and added to the STAGED list in apps/web-platform/infra/cloud-init-inngest.yml (precedent: #8408, registry-luks-escrow)" [brief] | - | descoped - justification: a STAGED or image edit changes `user_data` and force-replaces the sole scheduler, which the same brief forbids ("must NOT happen in this PR"); the brief asked to confirm the mechanism, and the finding (Reconciliation table) is that only a refresh-set member edit ships in place; ruled D1 by the CTO agent |
| 4 | "First read the earlier plan and its rulings" [brief] | Research Insights, Reconciliation | mapped |
| 5 | "confirm what mechanism delivers a new on-host script WITHOUT a host replace (the infra pull / config bundle) versus what would change user_data" [brief] | Reconciliation table, "Delivery and owner holds", Infrastructure (IaC) | mapped |
| 6 | "The probe must run read-only: it must never print the passphrase, never write to Doppler/Hetzner/Supabase" [brief] | Guard 2, design steps 2 to 7, acceptance criteria | mapped |
| 7 | "must emit a SOLEUR_* marker reachable from Better Stack/Sentry without SSH" [brief] | Observability, design step 8, Phase 3 | mapped |
| 8 | "so use 'Ref #9927'" [brief] | Acceptance criteria (PR body) | mapped |
| 9 | "legal questions (LUKS header off-host backup, Art. 17, disclosure wording) go to the CLO agent and are NOT decided here" [brief] | Domain Review (Legal), "What the probe can and cannot claim", follow-ups | mapped |
| 10 | "Persist every decision as a row of the `\| Item \| Class \| Ruling \|` table" [brief] | `decision-challenges.md` D1 to D11 | mapped |
| 11 | "a change under apps/web-platform/infra/ must not be applied by hand, it ships through the existing merge-time automation only" [brief] | Infrastructure (IaC) apply path | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `inngest-cutover-flip.sh` probe function | "Add a probe that runs `cryptsetup luksOpen --test-passphrase`" | asked |
| New suite `inngest-luks-key-probe.test.sh` | - | inferred - justification: `cq-write-failing-tests-before`, and Guards 1 to 3 need an executable suite or the guard contract rots |
| Real-tool loopback arm and sandbox rehearsal | - | inferred - justification: the 2026-09-21 learning (a stub that cannot refuse hid a rejected property); the sandbox claim needs one real run |
| `betterstack-logs-alerts.tf` paging alert | "must emit a SOLEUR_* marker reachable from Better Stack/Sentry without SSH" | asked |
| Dead-man alert | - | inferred - justification: CPO sign-off condition 3 and `hr-observability-as-plan-quality-gate` (a silent probe reads as health); ruled F4b by the CTO agent |
| `apply-web-platform-infra.yml` `-target` lines | - | inferred - justification: an alert absent from the allowlist only appears as drift (CTO B6) |
| ADR-282 amendment and the ADR-135 pointer | "First read the earlier plan and its rulings" | inferred - justification: the ADR row says the probe needs `user_data`, which this change falsifies; `wg-architecture-decision-is-a-plan-deliverable` |
| Runbook section 5c, `inngest-config-refresh.md` cross-reference | "hr-no-ssh-fallback-in-runbooks" | asked |
| `model.c4` description edits | - | inferred - justification: Phase 2.10 C4 completeness; the `inngestRedis` description states the detection gap this closes |
| Registry edits (shard legs, durations, affected-paths) | - | inferred - justification: the new suite must be scheduled in CI or it never runs |
| Follow-up issues | "PR body will use 'Closes #9927' only if the tracker's other items are done" | asked |

### Split Assessment

- Subsystems touched: 4 - `apps/web-platform/infra`, `.github/workflows`, `knowledge-base/engineering`, `scripts` (registry lines only)
- Planned files: 17 | Estimated changed lines: about 650 (function and call sites about 150, suites about 300, alerts about 100, docs about 100)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR. The script, its suite and the alerts share one marker and one closed vocabulary, and splitting them ships an alert for a marker nobody emits or the reverse. One carve-out: if the dead-man's read-only proof cannot run in the work session, split the dead-man pair and its `-target` line into a second PR rather than shipping an unproven 30-day window.

## Acceptance Criteria

> **Superseded in part by D12 and the 2026-10-26 review rulings (D13 to D17):** the dead-man alert is NOT in this PR (it follows an owner-authorized proof that Better Stack accepts `query_period = 2592000`, and is a blocking prerequisite of the bundle promotion, #11266). Wherever this section names the dead-man as shipped, read it as follow-up. Until it lands, probe silence, a persistent `indeterminate` and a mid-run death are detected only by the first-row verification and the `at=died` row; the alert route for those modes is none.

### Pre-merge (PR)

#### Functional Requirements

- [ ] FR1 `luks_key_probe_tick` exists in `inngest-cutover-flip.sh`, is called only from the four terminal-noop arm tails, and every verdict token is reachable in the suite with its `at=` literal and rc.
- [ ] FR2 The probe reads only `/etc/default/inngest-luks`; no Doppler call, no network call other than the existing phone-home POST, no write other than the stamp under `StateDirectory`.
- [ ] FR3 `git diff $(git merge-base origin/main HEAD) -- apps/web-platform/infra/cloud-init-inngest.yml apps/web-platform/infra/infra-config-install.sh apps/web-platform/infra/inngest-config-refresh-set.txt` is empty (merge-base form, so unrelated merges to main cannot flip it), and `bash apps/web-platform/infra/inngest-userdata-budget.sh` prints the same headroom before and after the change (804 B at plan time).
- [ ] FR4 CPO condition 2: a suite case proves a probe failure leaves the flag byte-identical and `flag_set` is never called by the probe, with the harness self-test on the recorder, and the disarm is tested outside the `||` context.
- [ ] FR5 CPO condition 3: the paging alert pages on `token=fail_` only (`indeterminate` absent from its SQL); the dead-man exists, self-arming, counts only `ok` and `fail_*` rows, and the read-only proof (Phase 3.2 a to e) is recorded in the PR before its `-target` line lands.
- [ ] FR6 CPO conditions 4 and 5: runbook section 5c has the pre-promotion checks, exact dispatch, promotion, first-row verification and revert steps, no SSH step, the claim limits, the key-charset assumption, the decision table for a page, the "no recovery if the header is lost" statement and the link to #9927 item 1.
- [ ] FR7 Follow-up issues 1 and 2 exist with trigger or due date and `Ref #9927`.
- [ ] FR8 PR body uses `Ref #9927` (no closing keyword; items 1, 3 to 8 remain), the web-redeploy notice for `apps/web-platform/infra/**`, the apply expectation (alert creates only from the infra apply; the deploy-pipeline-fix push to web hosts is expected) and no skip marker unless the plan read shows unreviewed drift.

#### Non-Functional Requirements

- [ ] NFR1 The suite computes the worst-case probe duration from the timeout constants (command timeouts plus kill graces plus the emit bounds, about 100 s) and asserts it is below `TimeoutStartSec=420` with at least 3x margin; no `sleep` and no loop in the function.
- [ ] NFR2 The sentinel key appears in no captured channel (Guard 2 census green).
- [ ] NFR3 `GUARD_REV` is unchanged (`"7761"`) and `cutover-inngest-workflow.test.sh` is green.
- [ ] NFR4 Either the sandbox rehearsal ran and its output (real mountinfo shape, `--disable-locks` result, `oom_score_adj` write) is quoted in the PR, or the runbook carries the literal line `sandbox: unverified` and the first-row verification accepts only `token=ok`.

#### Quality Gates

- [ ] `inngest-cutover-flip.test.sh`, the new suites, `inngest-carrier-vocabulary.test.sh`, `doppler-injection-bound.test.sh`, `inngest-config-refresh.test.sh`, `cutover-inngest-workflow.test.sh`, `terraform-target-parity.test.ts`, `workflow-file-size.test.ts`, the C4 suites and `python3 scripts/lint-guard-contract.py` pass.
- [ ] `soleur:engineering:review:user-impact-reviewer` and `soleur:engineering:review:observability-coverage-reviewer` run at review time.

### Post-merge (automated; owner holds listed separately)

- [ ] `gh run list --workflow apply-web-platform-infra.yml --commit <merge-sha>` concludes success and the plan read showed only the alert creates.
- [ ] `gh run list --workflow apply-deploy-pipeline-fix.yml --commit <merge-sha>` concludes success with `files_written == files_total`.
- [ ] `git fetch --tags origin && git tag --contains <merge-sha> --list 'vinngest-v*'` names the minted tag; the bot pin-bump PR is routine and is not merged by this work unless the owner asks.
- [ ] The two alerts exist and are unpaused in Better Stack (read via the provider state or `scripts/betterstack-query.sh`-adjacent tooling, no dashboard eyeballing).
- [ ] Owner hold (not done by this work, tracked by follow-up 2): pre-promotion checks, bundle build, digest promotion, first `token=ok` row from both channels.

## Test Scenarios

1. Each verdict: right key (rc 0) to `ok`; wrong key (rc 2) to `fail_passphrase`; `luksUUID` rc 1 plus `isLuks` rc 1 to `fail_header` (and `luksUUID` rc 1 with `isLuks` rc 4 to `indeterminate`); key file absent or empty to `fail_key_absent`; not on a mapper, `cryptsetup status` failing, `timeout` 124, tool absent (127), low `MemAvailable`, shield write refused, KDF rc 1 or 4 or 124 to `indeterminate` with the right `at=`.
2. Cadence: no stamp probes; an `ok` stamp younger than 24 h skips; an `ok` stamp older than 24 h probes; a non-ok stamp older than 1 h probes, younger skips; a `pending` stamp counts as non-ok; a probe that dies mid-run leaves a stamp that blocks a 30 s re-run; a failing `pending` write skips the probe.
3. Isolation: hung `cryptsetup` stub, failing stub, absent tools, a `return 1` wrapper, each with the flag, the exit status and the FSM rows compared byte for byte against a no-probe run in all four terminal-noop arms; the probe never runs in `armed`, `flipping`, `flushed`, `reflush`, `rollback`; the disarm tested outside the `||` context.
4. Seams: each new seam name is ignored without `--fixture-seams` and honoured with it; the derived seam set equals the list.
5. Secret census: sentinel absent from logger, phone-home, stamp, stub argv, stub env and stderr; the stub received exactly the sentinel bytes on stdin; a value with `=` and one with a trailing space are pinned.
6. Real tool: right, wrong, blank, trailing-newline on a file-backed LUKS2 container.
7. Alerts (text level in the suite): paging SQL matches the `token=fail_` shape and excludes `ok` and `indeterminate`; dead-man SQL is exactly the aggregate in Phase 3.2 with the `ok` / `fail_` recency terms and the anchored marker match; `-target` parity. Behaviour is established by the read-only substitution runs in Phase 3.2 (live marker gives 0, empty marker gives 0, shortened window gives 1), not by a ClickHouse engine in CI.

## Dependencies & Risks

- **Delivery depends on owner acts** (bundle build, digest promotion); until then the probe is inert on the dedicated host and both alerts are quiet by design. Mitigation: follow-up 2 tracks delivery with a due date; the first-row verification is a documented, read-only command.
- **FSM edit risk** (the script is the only control channel of the sole scheduler; a broken script kills the no-SSH rollback channel and the engine has no post-apply health check or auto-revert). Mitigation: the CTO's mandatory isolation, Guard 1, the byte-identical-flag case, pre-promotion `bash -n` and fixture smoke checks, a revert branch kept green in advance (no probe-free bundle can exist before a revert merges, D13), a single PR with a stricter threshold and the user-impact reviewer.
- **Sandbox behaviour of `--disable-locks` and the real `findmnt` shape under `ProtectSystem=strict` and a bind-mounted `ReadWritePaths`** is reasoned and measured only on a file container; Phase 2.3 measures it under the unit's properties or the runbook says `sandbox: unverified`.
- **30-day `query_period` is unproven** (provider does not validate; longest precedent 27 h). Mitigation: Phase 3.2 gate, fallback ladder, split-PR carve-out.
- **argon2id memory** on a 4 GB host that also runs redis (256 MB) and the scheduler: the `luksDump` pre-check returns `indeterminate` instead of risking an OOM; the shield makes the probe the first victim. The hourly re-run after a non-`ok` token repeats this; the runbook notes it.
- **Standing drift** from the bot pin-bump PR is routine and shows only in the drift detector; the web-host push on merge is the existing channel.
- **Honest limit:** the probe detects, it does not recover; no header backup exists and a failed header has no recovery (ADR-282). A green probe also does not prove the Doppler copy matches the host file or that the by-id volume equals the mapper's device.

## References & Research

- Issue #9927 (items 1 to 10; re-evaluation criteria: 2027-01-08 or the next planned host replace); #8408 (registry escrow precedent); #9879, ADR-282, ADR-135; #10966 (cutover trio retired); `knowledge-base/project/plans/archive/20261025-173406-2026-10-24-feat-inngest-host-replace-window-prework-plan.md` and `knowledge-base/project/specs/archive/20261025-173406-feat-one-shot-inngest-window-prework/` (D1 to D13; the keeper trio design this plan replaces for now).
- Runbooks: `inngest-server.md` (bootstrap-image release, production envelope), `inngest-luks-cutover-6894.md` section 5c, `inngest-config-refresh.md`.
- Code: `apps/web-platform/infra/inngest-cutover-flip.sh`, `inngest-cutover-flip.service`, `inngest-config-refresh-set.txt`, `infra-config-install.sh` (`DEST_SPEC`), `server.tf` (`deploy_pipeline_fix`), `apply-deploy-pipeline-fix.yml`, `cloud-init-inngest.yml` (`inngest-luks-open.sh`, `inngest-boot-phone-home.sh`, STAGED), `cloud-init-registry.yml` (`registry-luks-escrow.sh`), `betterstack-logs-alerts.tf` (`inngest_luks_wrong_volume`, `luks_monitor_host_timer_dark`), `vector.toml` Source 4.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, holds only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; this one declares `single-user incident` and carries the CPO conditions.
- The flip script's pre-trap window and its command-position sweep (one `local x=` per line, no loop body ending in a `[[ ]] &&` short-circuit, `n=$((n+1))` not `(( n++ ))`) bind new code in that file even though the probe runs after the trap is installed.
- In the `( f ) || true` context `errexit` and the ERR trap are suppressed inside the subshell (measured), so a failing command does NOT abort the probe body: every step must test its own rc and the probe must never rely on `set -e`. The `trap - ERR` disarm matters only for a call outside that context and must be tested there.
- Do not copy the registry probe's `sleep 300` memory retry: it would hold the only control poll.
- `GUARD_REV` must not move (two suites pin it); the first probe row is the delivery proof.
- A `raw LIKE` prefilter in the dead-man SQL would count webhook payloads that quote the marker (this PR's own body, the runbook) as live probe rows and mask a dead probe; use the anchored `position(JSONExtractString(raw,'message'),marker)=1` form and filter on the `dt` column, not the `time` alias.
- The phone-home builds `<marker> stage=<arg> <detail>`: do not put a `stage=` key in the detail, and put no hash, UUID or device id in the row (its redaction eats 32-plus hex runs).
- A new alert resource without its `-target` line only appears as drift; the dead-man's line lands only after its read-only proof.
- Editing the script re-fires `apply-deploy-pipeline-fix.yml` through the `triggers_replace` hash; the skip marker for that workflow is a different token from the infra one and is not used here.
- Plan-time numbers (804 B headroom, the cryptsetup rc table) are dated 2026-10-26 measurements on a file container; re-measure at work time and cite the command, not the figure.
