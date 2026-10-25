---
title: "feat: code-only prework for the Inngest host-replace window"
date: 2026-10-24
slug: inngest-host-replace-window-prework
branch: feat-one-shot-inngest-window-prework
issue: 10390
closes: none (Ref #9927 items 1 and 2, Ref #10112 item 1, Ref #10390; all are trackers, no closing keywords)
type: feat
priority: p2
domain: engineering
lane: cross-domain
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
---

# feat: code-only prework for the Inngest host-replace window

## Enhancement Summary

**Deepened on:** 2026-10-24 (headless, bounded pass; no full agent fan-out, per the coordinator's instruction to finish)
**Gates run mechanically:** 4.6 User-Brand Impact (present, threshold `aggregate pattern`), 4.7 Observability (5 fields present, no SSH, allowlisted verb, literal `expected_output`, `credentials_required` declared), 4.8 PAT-shaped variables (none), 4.10 Encryption Posture (present, `does_not_defend` non-empty), 4.11 Guard Contract (`python3 scripts/lint-guard-contract.py` green, 3 guard entries), 4.12 Scope Check (one unfenced section, every ask mapped, inferred rows justified). 4.9 UI-wireframe and 4.55 downtime halts: not triggered (no UI surface; no host is touched by this work).
**Citation sweep:** every `knowledge-base/` path in the plan resolves except `2026-10-counsel-review-9927-header-backup.md`, which is a Files-to-Create item written by the CLO at PR-3 time; rule ids resolve to active rules (one wrong id fixed: `wg-when-deferring-a-capability-create-a`); every cited issue and PR number was read live this session.
**Research agents already used during planning:** repo-research-analyst, learnings-researcher, functional-discovery (no overlap), CTO (rulings D1 to D13), CLO (`clo-wording.md`). A terraform-architect review was launched and returned no findings before the session ended; its checks are carried as explicit PR-3 work items below.

### Key improvements found in the deepen pass

1. The discoverability probe originally pointed at `scripts/betterstack-query.sh --help`, which prints a credentials error, not a literal. Replaced with a local `grep -l` that prints `inngest-luks-keeper.sh` once the script emits the row marker; the credential-gated live read stays under `credentials_required`.
2. The wrong rule id was corrected (see above).
3. PR-1 gained a sweep item: `betterstack-logs-alerts.tf` mentions `inngest-luks-cutover` twice and `vector.toml` carries the cutover tag in three lists (CTO: leave the stale tags, tracked follow-up; the two alert-file mentions must be classified at work time as comment or live source filter, because deleting the unit removes its rows from that filter's population).
4. `inngest.test.sh` pins `DROPIN_ACK_UNITS=("inngest-cutover-flip.service" "inngest-luks-cutover.service")` at line ~2848 and `-eq 2` at ~2963; the keeper replaces the second entry, so the count assertion stays 2.
5. The mint script derives carriers from `cp apps/web-platform/infra/<file>` lines in the build workflow (regex `^[[:space:]]*cp apps/web-platform/infra/[A-Za-z0-9._-]+ `), so keeper file names must match `[A-Za-z0-9._-]+` and be added as `cp` lines to be treated as carriers; the work phase confirms with `--dry-run`.

### New considerations discovered

- Main moved after the window package (#10951, floor 5 to 6 with an ordering gate): added as window precondition P0.
- The cutover script is also a signed refresh-set member, so an edit on main ships to the live host through the bundle path once a bundle is built: PR-1 deletes rather than edits it.
- The 300 B bar was prose only; PR-D makes it an enforced, sunset-dated floor.

### Deferred-to-work verification list (each is an explicit task, not an assumption)

host `curl` >= 7.75; boot-token drop-in shape for the keeper unit; `infra-config-refresh.test.sh` lockstep on `DEST_SPEC`; offline `terraform validate` and count=0 `-target` behaviour on terraform 1.10 for the gated bucket; `prevent_destroy` plus count flip comment; `terraform-target-parity` / ledger `live_coverage_floor` / `doppler-config-inventory.txt` demands for the new resource; `workflow-file-size` headroom after the extra `-target` line; whether `cloud-init-user-data-size.test.ts` is red on main.

## Overview

Prepare, in code only, everything the next approved Inngest host-replace window would otherwise have to carry, so the window itself becomes one dispatch plus verification. Nothing in this work dispatches a replace, writes to Hetzner, Doppler, Supabase or R2, mints a credential, runs `op=resume`, or touches the #10382 rotation.

Four deliverables, split into themed PRs (section "PR split and merge order"):

- (b) fix the stale "Better Stack retention is ~3 days" comment in the image-baked `inngest-server-flip-guard.sh` (now 90 days, `betterstack-log-query.md`).
- (c) #10112 item 1: remove the plaintext vocabulary (`PLAIN_ID`, `STAGING_NAME`, `/mnt/data-luks`, the `rollback)` arm) from `inngest-luks-cutover.sh` and its test. Measured reality: those symbols are the copy-and-swap FSM itself, so the CTO ruled the whole cutover trio is retired from the image (D1).
- (d) #9927 item 2: an on-host key-continuity probe (`cryptsetup luksOpen --test-passphrase`) baked in the image and added to the STAGED list.
- (e) #9927 item 1: the LUKS header off-host backup per the CLO ruling of 2026-10-15, declared in Terraform but gated off, with the credential mint left as an owner step written as a runbook entry.

The user_data margin is the binding constraint. Re-measured offline today: 256 B against the 300 B the window needs. The byte plan below reaches 364 B on the final tree.

Authority: operator go 2026-10-24 for prework PRs plus the #9927 item 1 header-backup build. Technical forks were ruled by the CTO agent and legal wording by the CLO agent (rows D1 to D13 in `knowledge-base/project/specs/feat-one-shot-inngest-window-prework/decision-challenges.md`; CLO text in `clo-wording.md` beside it).

## Research Reconciliation - Spec vs. Codebase

| Claim in the brief / window package | Reality (measured 2026-10-24 on `origin/main` c15ed71796) | Plan response |
|---|---|---|
| "user_data headroom is 256 B" | Confirmed: `bash apps/web-platform/infra/inngest-userdata-budget.sh` gives stored 32,512 B, cap 32,768 B, headroom 256 B, rc 0. | Byte plan below. |
| "Runbook A1 requires >= 300 B" | The only statement of the 300 B bar is prose in `runbooks/inngest-server.md` Production Envelope A1 ("green with at least 300 B margin on the trial merge"). No script, test or workflow enforces it. | CTO D6: add `--min-headroom` to the budget script and call it with 300 from `infra-validation.yml`, in PR-D together with the margin. |
| "#10112 item 1: drop PLAIN_ID, STAGING_NAME, /mnt/data-luks, rollback arm" | `inngest-luks-cutover.sh` (961 lines) is the plaintext-to-LUKS copy and swap FSM; those names run from line ~119 to ~808. `op=luks-rollback` was already retired (#8285 PR B). #10081 (cited as parked) MERGED 2026-10-15. The script is also a member of the signed config-refresh set (`inngest-config-refresh-set.txt`). | CTO D1: retire the trio, drop the refresh-set member in the same PR, leave dispatcher `op=luks-cutover` inert (follow-up issue). |
| "Image release needs an operator tag push" | Not so: `mint-inngest-bootstrap-tag.yml` auto-mints `vinngest-vX.Y.Z` on a push to main that changes image inputs and dispatches the build from main; the bot opens the pin-bump PR (ADR-232). | No operator tag push. Merge order controls how many tags are minted. |
| "#9927 item 1 uploader credential delivery costs user_data" | Any new secret NAME in `soleur-inngest/prd` must be added to the boot identity regex in `cloud-init-inngest.yml` (exact-set check `n_total -ne n_inngest`), else the next boot FATALs. Existing live names `INNGEST_LUKS_CUTOVER` and `INNGEST_LUKS_ACTIVE_VOLUME_ID` must stay admitted. | CTO D4/D5: ONE owner-written secret `INNGEST_LUKS_HDR_PUT`, exact name appended (~13 B). |
| "terraform declared, sibling of workspaces-luks-header.tf" | That sibling creates the bucket AND two `doppler_secret` at merge (in the merge `-target` set). Pinned provider cloudflare 4.52.7 `cloudflare_r2_bucket` exposes only account_id, id, location, name (no jurisdiction; measured offline). | CTO D4: count-gated bucket, default off; no `doppler_secret`. D7: ship `WEUR` with Chapter V wording, never "EU". |
| Window package preconditions | Written at eb7df4de6e, before #10951 (c15ed71796) raised the identity floor 5 to 6 with an ORDERING GATE in `cloud-init-inngest.yml`: no host-replace dispatch between that merge and the promotion apply of `INNGEST_CONFIG_DIGEST`. | New window precondition P0 (section "Window preconditions delta"). Prework builds none of it. |
| "package: flip-guard feeds sha256 vars" | The sha256 vars in `inngest-host.tf` are inngest-cli, vector and doppler tarball digests; none hashes the flip guard. The edit reaches the host through the image digest pin (same length) and, if a bundle is built later, the refresh channel. | Comment edit is user_data-neutral (0 B net). |
| "Open PRs carrying any of this: none" | Re-checked: #10692 (draft, unrelated) and #10936 (merged 2026-10-24) are not touched. Open code-review issues touching planned files: #10112 (this work), #10243 (nft comment, acknowledged, not folded in). | See "Open Code-Review Overlap". |
| "the host's flip FSM token rw -> r (#9927 item 4)" | CTO 2026-10-23: does NOT ride; keep read/write until #6890. | Out of scope; recorded. |

## Research Insights

### Premise Validation

Checked live: #9927, #10112, #10390, #9755, #6890 OPEN; #10081 MERGED 2026-10-15; #10936 MERGED; #10692 open draft; #9786 CLOSED. Cited paths all exist on `origin/main`. The mechanism check against the ADR corpus: ADR-142 ("No key escrow") and ADR-282 (Alternatives rows "Escrow the passphrase or header" Rejected, "On-host header backup or luksOpen probe" Deferred) are the records this work supersedes in part, via the CLO-gated markers. Stale premises found: the package's "owner go due 2026-11-05 / pending one replace" is spent (replace ran 2026-10-20, run 39400431311); the package's preconditions predate #10951; #10081 is no longer parked.

### Property List

1. A replaced host carries a key-continuity signal: a daily row proves the Doppler passphrase still opens the LUKS device (no mapper opened).
2. The current LUKS header has a recoverable off-host copy once the owner activates it, and only the current header is retained.
3. No window-critical edit is possible that leaves less than 300 B of user_data margin on the final tree.
4. The image carries no plaintext-volume vocabulary.
5. The flip guard comment states the true retention.
6. The merge-triggered production apply creates no bucket and writes no secret before the owner's go.
7. Legal records state that Art. 32(1)(c) is still NOT provided.

### Cut List (mechanism, property, what already covers it)

- A second trio for the uploader: property 2 is served by one combined trio (24 B saved, shared key read).
- `doppler_secret` for bucket and endpoint: property 6 served by one owner-written secret; each Terraform-owned name would need its own regex edit and tfstate would hold values.
- A stub cutover script kept in the image: serves no property; costs the bytes property 3 needs.
- A dead-man heartbeat for the keeper, dispatcher `op=luks-cutover` retirement, stale `vector.toml` tags, removal of the two cutover names from the regex: not needed for any property; tracked issues (D13).
- A separate Doppler config or service token for the write-only key: CLO D8 says not required.
- Prefix wildcard admission `HEADER_[A-Z_]+`: weakens the exact-set tripwire (D5).

### Institutional learnings applied

- `2026-07-18-image-baked-and-latent-is-a-claim-verify-a-published-tag-exists.md`: baked edits ship only through a published, pinned tag; verify with `git tag --contains <merge-sha> --list 'vinngest-v*'`.
- `2026-07-16-a-drift-guard-can-recreate-its-own-bug-and-a-forced-replace-from-a-stale-pin-ships-nothing.md`: a replace from a stale pin ships nothing; the window preconditions must include the pin check.
- `2026-10-08-a-pin-copied-into-three-suites-had-one-detector-and-two-silent-copies.md`: the digest literal lives in several suites; the bot pin-bump handles them, never hand-edit.
- `2026-09-21-my-escrow-suite-stubbed-the-one-tool-that-would-have-refused-it.md` and `2026-09-19-every-systemd-claim-i-reasoned-was-inverted-by-a-thirty-second-measurement.md`: run the real unit semantics once in a rehearsal, do not stub the tool that refuses; measure oneshot and timer behaviour.
- `2026-08-04-the-code-i-read-as-not-encrypted-was-a-default-errno-bucket-and-my-capture-forged-it.md`: `cryptsetup isLuks` rc 1 is a default bucket; the probe must treat rc and stderr separately and never branch to a destructive path.
<!-- lint-infra-ignore start -->
- `2026-07-03-dark-launch-pr-must-exclude-operator-prerequisite-infra.md`: credential-gated infra must not ride a merge-triggered apply (basis for the count gate).
<!-- lint-infra-ignore end -->
- `2026-08-12-i-proved-the-transform-and-left-its-application-and-its-size-unpinned.md`: measure with the same expression the host gets (the budget script does).
- `2026-07-26-cloud-init-comment-is-a-live-host-input-and-an-unreadable-vendor-limit-decays.md`: comment edits in the template are ForceNew inputs; this plan edits non-comment lines on purpose and re-measures.
- Gap: no learning exists for an R2 write-only header key; this plan derives it from code, ADRs and the CLO ruling.

### Measurements (offline, planner, scratch copy; terraform builtins only, no credentials)

Budget script run in `/tmp/claude-1000/.../scratchpad/budget` on copies of the five files it reads. Measured pairs (each from a fresh copy of main unless noted):

| Variant | Headroom |
|---|---|
| Baseline (origin/main) | 256 B |
| One new trio added to STAGED | 236 B |
| Two new trios added | 212 B |
| Two new trios, cutover trio dropped from STAGED | 224 B |
| ... plus quiesce-loop and service-status references to the cutover FSM removed | 300 B |
| ... plus the two volumes-file lines removed | 356 B |
| ... plus prefix admission `HEADER_[A-Z_]+` (16 B) | ~340 B |
| ONE keeper trio replacing the cutover trio, quiesce references removed, volumes-file lines removed (no admission yet) | 376 B |
| Same, plus exact-name admission `\|LUKS_HDR_PUT` | **364 B** |

Final tree: **364 B**, direct measurement of the full set; clears the 300 B bar and the CTO's 350 B target. Per-item contributions of the final set against the 256 B baseline: STAGED swap (one keeper trio replaces the cutover trio) -12 B (derived: 376 - 256 - 76 - 56); quiesce-loop and service-status references +76 B; volumes-file lines +56 B (measured pair, 300 to 356); exact-name admission -12 B (376 to 364); net +108 B, total 364 B. Cost of the alternatives measured: four-name admission list 36 B vs prefix 16 B vs exact name ~12 B.

Floors that stay: the identity check `-lt 6` floor; `INNGEST_LUKS_CUTOVER` and `INNGEST_LUKS_ACTIVE_VOLUME_ID` remain admitted because the live Doppler config holds both names.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Build the code-only prework for the Inngest host-replace window (Ref #9927 items 1 and 2, Ref #10112 item 1, Ref #10390; no closing keywords, all are trackers)" | PR-1, PR-2, PR-3, PR-D; `Ref` only in every PR body | mapped |
| 2 | "(a) image-baked changes only, since user_data headroom is 256 B vs the 300 B required (run apps/web-platform/infra/inngest-userdata-budget.sh offline; keep margin >=300 B on the final tree, shed bytes if needed, CTO rules on how)" | Byte plan; PR-D; D2, D5, D6 | mapped |
| 3 | "(b) inngest-server-flip-guard.sh Better Stack retention comment fix (~3 days -> 90 days per betterstack-log-query.md)" | PR-1 task 1.1 | mapped |
| 4 | "(c) #10112 item 1 drop plaintext vocabulary from inngest-luks-cutover.sh + its test (PLAIN_ID, STAGING_NAME, /mnt/data-luks rollback arm)" | PR-1 tasks 1.2 to 1.6; D1 | mapped |
| 5 | "(d) #9927 item 2 on-host key-continuity probe baked in the image (cryptsetup luksOpen --test-passphrase, precedent #8408), added to the STAGED list" | PR-2 (keeper trio, probe phase) and PR-D (STAGED); D3 | mapped |
| 6 | "(e) #9927 item 1 LUKS header off-host backup per CLO ruling 2026-10-15 conditions ... terraform declared but the credential mint is the owner's later step, so write the owner step as a runbook entry, do not mint" | PR-2 (keeper uploader phase), PR-3 (gated bucket, ledger, legal text, runbook entry); D4, D7, D8 | mapped |
| 7 | "Split into sensible themed PRs; the image release (tag vinngest-vX, bot pin-bump PR) is a post-merge step: stop and surface it if it needs an operator tag push" | PR split table; no operator tag push needed (auto-mint verified) | mapped |
| 8 | "Any merge under apps/web-platform/infra fires the production apply: check preflight, use [skip-web-platform-apply] ... ONLY if the apply would include unreviewed drift ... give web-redeploy notice per #9755 text" | Per-PR apply table; PR-body notice paragraph | mapped |
| 9 | "Legal wording goes to the CLO agent; technical forks to the CTO agent, not the operator." | `clo-wording.md`; `decision-challenges.md` | mapped |
| 10 | "The plan must (1) re-measure the user_data margin offline ... and state the byte plan for the final tree (>=300 B)" | Measurements; Byte plan | mapped |
| 11 | "(2) split the work into themed PRs with an explicit merge order and say which need an image release / pin bump" | PR split table | mapped |
| 12 | "(3) state per PR whether the merge fires an apply and whether [skip-web-platform-apply] is needed" | PR split table | mapped |
| 13 | "(4) route the CLO-gated wording (PA-13(g) TOM, ADR-142/282 supersede text) through soleur:legal:clo" | `clo-wording.md` | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Retire the cutover trio, refresh-set member, STAGED and quiesce references | "drop plaintext vocabulary from inngest-luks-cutover.sh + its test" and "shed bytes if needed, CTO rules on how" | asked (CTO D1) |
| `--min-headroom` floor in the budget script and `infra-validation.yml` | "keep margin >=300 B on the final tree" | asked (CTO D6) |
| Single owner-written secret `INNGEST_LUKS_HDR_PUT` and its regex admission | "write-only host credential" and "terraform declared but the credential mint is the owner's later step" | asked (CTO D4/D5) |
| `count` gate on the bucket | "do not mint" and "NOT authorized: any Hetzner/Doppler/Supabase/R2 write" | asked (CTO D4) |
| Better Stack alert for the keeper | "added to the STAGED list" plus `hr-observability-as-plan-quality-gate` | inferred - justification: a probe whose failure reaches no alert fails the observability gate; modelled on `betterstack-logs-alerts.tf` |
| C4 and ADR-297 | "ADR-142/282 supersede markers" | inferred - justification: plan Phase 2.10 makes the ADR/C4 update part of the change that creates the decision; ADR-297 records the keeper trust edge and the retirement |
| Window precondition P0 (promotion apply) | "re-verify every claim live" | asked |
| Follow-up issues (dispatcher retirement, heartbeat, jurisdiction pin) | "Ref #9927 ... trackers" and `wg-when-deferring-a-capability-create-a-tracking-issue` | inferred - justification: deferral tracking is a workflow gate |

### Split Assessment

- Subsystems touched: 5 - `apps/web-platform/infra/` (carriers, cloud-init, tf, tests), `.github/workflows` and `.github/scripts` (image build and check), `scripts/` (ledger, shard manifests, baselines), `knowledge-base/` (ADR, legal, runbook), `plugins/soleur/test/` (parity).
- Planned files: > 25 across the four PRs; each PR individually stays under 25 except PR-1 (test sweep, bounded by `git grep`).
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines - exceeded.
- Recommendation: split - four PRs (PR-1, PR-2, PR-3, PR-D) along the image / legal / user_data boundaries below.

## User-Brand Impact

- **If this lands broken, the user experiences:** the sole Inngest scheduler host fails its next boot or replace (user_data over cap, a name rejected by the boot identity check, a missing baked file), so scheduled reminders, crons and agent runs stop firing until the host is repaired; queued jobs sit in the retained AOF volume.
- **If this leaks, the user's workflow is exposed via:** a read-capable R2 credential or a mis-scoped write key (the LUKS header copy plus the Doppler passphrase would open a copied volume); the plan stores no read-capable credential anywhere and refuses a readable key in the uploader.
- **Reviewed residuals (2026-10-25 panel):** (a) the trio stays as an inert file on already-provisioned hosts until the next replace; (b) the dispatcher's `op=luks-cutover` can still write a flag nothing consumes (its guards refuse the op; retired in the D13 follow-up); (c) the bot pin-bump PR for this merge auto-merges when the zot mirror is healthy, so an image without the keeper could be pinned before PR-2 lands: window precondition P1 (`git tag --contains`) is what gates the replace, and the bump PR for the last tag is the only one to merge.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** this is code-only prework that touches no live host and mints nothing; the failure that matters materializes at the window and hits the shared scheduler (many users), not one user. Counter-view recorded as D11 (single-user incident because the store is a sole copy); stays at aggregate unless the operator says otherwise.

## Problem Statement / Motivation

The window package (prepared 2026-10-23) lists five code-only items that must merge before any replace: the flip-guard comment, the cutover-script vocabulary, the key-continuity probe, the header backup, and a byte shed. The package assumed they fit; the live measurements show the user_data margin (256 B) is below the window bar (300 B), that the cutover "vocabulary" is the whole FSM, and that new Doppler names are blocked by an exact-set boot check. This plan turns those findings into a buildable, ordered set of PRs.

## Proposed Solution

### Final shape

- **Image-baked (no user_data bytes):** one combined keeper trio `inngest-luks-keeper.{sh,service,timer}`; deletion of `inngest-luks-cutover.{sh,service,timer}` and its install and enable blocks in `inngest-bootstrap.sh`; the flip-guard comment fix; vector tag for the keeper's rows.
- **user_data (PR-D only, last):** STAGED list swap, quiesce-loop and service-status-list reference removal, removal of the two volumes-file lines, `|LUKS_HDR_PUT` admission. Net +108 B of margin.
- **Terraform (PR-3):** `inngest-luks-header.tf` with a count-gated R2 bucket, default off; an inert `-target` line; ledger row; no secrets in state.
- **Docs and legal (PR-3, CLO-gated):** Art. 30 register PA-13 (e) and (g)(15) markers, ADR-142 and ADR-282 supersede markers, compliance-posture pointer, ADR-297, C4 edit, runbook owner entry; counsel-review audit file.

### Keeper trio design (CTO D3, F3)

`inngest-luks-keeper.sh` (root oneshot, fired by the timer). Phases in one run:

1. Resolve the LUKS device with `findmnt -no SOURCE /mnt/data` then `cryptsetup status <mapper>` and read the `device:` line - no volume id vocabulary, no extra user_data.
2. Read `INNGEST_REDIS_LUKS_KEY` under `doppler run --only-secrets` using the same token drop-in shape the cutover service used (the drop-in replaces it in the `DROPIN_ACK_UNITS` set so the pinned count stays 2). Key goes on stdin to `cryptsetup luksOpen --test-passphrase --key-file -` (precedent `luks-monitor.sh`). Probe row `probe=ok|fail reason=`; `fail` exits 1.
3. Header: `cryptsetup luksHeaderBackup` to a 0600 file under `/run`, sha256, compare with the marker in `StateDirectory`; on a changed or absent marker upload; the marker is lost on replace, causing one idempotent re-upload. This covers "re-take after every key change".
4. Upload (only if `INNGEST_LUKS_HDR_PUT` present): parse `endpoint|bucket|key_id|secret`; require the endpoint to match `^https://[0-9a-f]{32}(\.eu)?\.r2\.cloudflarestorage\.com$`; before the first upload GET a random nonexistent key - a 404 means the credential can read, so emit `backup=refused reason=credential_readable` and upload nothing (write-only is enforced technically, not only by process); then `curl --aws-sigv4` PUT of the fixed object key (overwrite is the purge). Absent secret: `backup=unconfigured`, exit 0, no network call.
5. Row: one JSON marker `SOLEUR_INNGEST_LUKS_KEEPER` under its own `SyslogIdentifier`, plus an `ExecStopPost` unit-exit row like the cutover service had.
6. Timer: `OnBootSec=10min` (a replaced host emits inside the window), daily `OnCalendar` at 03:17 UTC, `RandomizedDelaySec=30min`, `Persistent=true`.

Open checks the work phase must close before PR-2 is marked ready (CTO listed them unverified): host `curl` is >= 7.75 (needed for `--aws-sigv4`; if older, stop and re-rule); how the boot token drop-in reaches the cutover service today (copy it exactly); whether `infra-config-refresh.test.sh` forces a lockstep `DEST_SPEC` removal for the retired member.

### Bootstrap install (image, `inngest-bootstrap.sh`)

Same pattern as the cutover trio: install the keeper trio if staged, else log `install_missing` plus phone-home `luks-keeper-install-MISSING` (non-fatal); the timer is enabled in the image's enable block. The cutover install block (about lines 1531 to 1545) and its enable block (about 1851 to 1854) are deleted in PR-1 and the keeper block is added in PR-2; run the bootstrap tests after both.

## Implementation Phases (by PR)

### PR-1 - "baked-carrier hygiene": flip-guard comment + retire the cutover trio (image-affecting)

- 1.1 `inngest-server-flip-guard.sh`: replace the sentence "Better Stack retention is ~3 days against a 12-day-old boot" with a dated, true statement: it was a free-tier figure when written (2026-08); the source `soleur-inngest-vector-prd` now reports 90-day retention (`betterstack-log-query.md`, measured 2026-09-04). Comment only; no behaviour change. The file is a refresh-set member: run `inngest-server-flip-guard.test.sh` and `inngest-config-bundle-pack.test.sh`.
- 1.2 Delete `inngest-luks-cutover.sh`, `.service`, `.timer`, and `inngest-luks-cutover.test.sh`.
- 1.3 `build-inngest-bootstrap-image.yml`: remove the three `cp` lines, three `COPY` lines, the `chmod` operand and the ENTRYPOINT `cp` operands for the trio; mirror in `.github/scripts/check-inngest-bootstrap-build.sh` and the `paths:` of `check-inngest-bootstrap-build.yml`. (PR-2 adds the keeper to the same sites.)
- 1.4 `inngest-bootstrap.sh`: delete the cutover install block and its `DEDICATED_LUKS_CUTOVER` enable block. `inngest-config-refresh-set.txt`: drop the member; update every "five committed members" assertion and message (`build-inngest-config-bundle.yml` empty-set error text, `inngest-config-bundle-pack.test.sh`, `inngest-config-bundle-mirror.test.sh`, `inngest-config-refresh.test.sh`; derive the list with `git grep -n 'five\|refresh-set'`). Keep the `DEST_SPEC`/`FILE_MAP` rows in the root helper unless the refresh test demands lockstep removal (CTO: do not edit the root helper for hygiene).
- 1.5 Tests that move with the retirement: `inngest.test.sh` (`DROPIN_ACK_UNITS` pin ~line 2965 and service/timer asserts ~2791/2978), `cloud-init-inngest-provision-unit.test.sh` (quiesce battery ~957 to 1024, 1136, 1367), `inngest-luks-sole-copy.test.sh`, `inngest-redis-luks.test.sh` (`PLAIN_ID` strip needles ~397, controls ~408), `inngest-redis-luks-import-rehearsal.test.sh`, `ci-deploy.test.sh` (`QI_PIN_B` ~7571), `apps/web-platform/test/infra/betterstack-send-failed-alert.test.sh`, `apps/web-platform/test/infra/inngest-luks-wrong-volume-alert.test.sh`, `scripts/lib/inngest-probe-row.test.sh`, `scripts/guard-vacuity-floor.test.sh`, `.claude/hooks/grep-q-pipe-guard.test.sh`, `plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts`, `plugins/soleur/test/sole-copy-drift-check.test.sh`; registrations `suite-shard-legs.tsv` (two copies), `suite-durations.tsv`, `scripts/ci-pr-affected-audit.baseline.tsv`, `scripts/lib/test-affected-paths.sh`. Derive the final list with `git grep -ln 'inngest-luks-cutover'` on the branch (the research inventory is the floor, not the ceiling).
- 1.6 Do NOT edit `cloud-init-inngest.yml` in this PR (PR-D owns user_data). Because the image no longer carries the trio while the old cloud-init still lists it in STAGED, the staging copy (`docker cp ... || true`) stages nothing and the new bootstrap never looks for it - harmless.
- 1.7 Dispatcher: no edit. `scripts/cutover-inngest.sh` G3 message that names `install_missing` stays as is; file the follow-up issue (D13).

Apply (corrected after the 2026-10-25 review panel): the merge fires the infra apply for `apps/web-platform/infra/**`; its `-target` set excludes `hcloud_server.*`, so no host is replaced. It is NOT a no-op: the `server.tf` trigger set and `hooks.json.tmpl` change, so `deploy_pipeline_fix`, `infra_config_handler_bootstrap` and `deploy_pipeline_fix_web2` re-fire on the live web hosts (the intended push channel, ordered bootstrap-first; the web-redeploy notice per #9755 applies). No `[skip-web-platform-apply]`. Image: yes - carriers changed, auto-mint cuts a tag.

user_data (corrected): the deleted `DEST_SPEC` row in `infra-config-install.sh` is embedded in the inngest host's `user_data` (`inngest-host.tf` `file()`), so this PR does change it, by about -24 B: measured headroom is now 280 B (was 256 B). No merge-time apply targets `hcloud_server.inngest`; the delta shows only in the drift detector and the preflight read, next to the known #10835/#10768 drift. PR-D's byte plan starts from 280 B, not 256 B.

### PR-2 - "keeper trio": key-continuity probe + gated header backup uploader (image-affecting)

- 2.1 New `inngest-luks-keeper.sh`, `.service`, `.timer` (design above). Name matches the mint path glob `apps/web-platform/infra/inngest*`.
- 2.2 `inngest-bootstrap.sh`: install and enable block for the trio (non-fatal install_missing).
- 2.3 `build-inngest-bootstrap-image.yml` and `.github/scripts/check-inngest-bootstrap-build.sh`: add the three `cp`, three `COPY`, `chmod` operand and ENTRYPOINT operands; `check-inngest-bootstrap-build.yml` paths. `mint-inngest-bootstrap-tag.sh` derives carriers from `cp` lines automatically - confirm with `--dry-run`.
- 2.4 `vector.toml`: add the keeper `SyslogIdentifier` to the three `include_matches` lists (the Better Stack shipper); `journald-config.test.sh` if it enumerates tags.
- 2.5 `betterstack-logs-alerts.tf`: new `logtail_exploration_alert` on `probe=fail` or `backup=fail|refused` (model: lines ~242 to 305; honour the paid-tier gate used by sibling alerts). This is a normal create on merge apply - the only non-zero plan item in the whole set; the preflight plan read must show exactly it plus the expected drift.
- 2.6 Tests (`inngest-luks-keeper.test.sh`): stub `cryptsetup`, `findmnt`, `curl` and `doppler` per the registry-escrow precedent; PLUS one arm that runs the real script against a loopback LUKS device where root and loop devices exist (precedent `inngest-redis-luks-loopback.test.sh`), never against a production volume. Cases are listed in Test Scenarios and the Guard Contract.
- 2.7 Register the suite: `suite-shard-legs.tsv` (both copies), `suite-durations.tsv`, a `run: bash` step in `infra-validation.yml`, `scripts/ci-pr-affected-audit.baseline.tsv`.
- 2.8 `scripts/lint-encryption-posture.py`: run it; the new `luksOpen --test-passphrase` site must satisfy its mapper-less site rule (a probe has no mapper operand).
- 2.9 STAGED membership: STAGED is user_data and belongs to PR-D (image first, cloud-init last). PR-2 must NOT make `inngest-host.test.sh` require the keeper names in STAGED (`FLIP_REQUIRED` is derived from `/tmp/inngest-[a-z-]+\.[a-z]+` in `inngest-bootstrap.sh`, so check how the derivation treats the new gate name and adjust only the derivation, not the STAGED assertion); PR-D moves the requirement.

Apply: fires; plan = the new alert create only. No skip marker. Image: yes.

### PR-3 - "gated header bucket + legal records" (no image carrier)

- 3.1 `inngest-luks-header.tf`: `variable "inngest_luks_header_backup_enabled"` (bool, default false, non-sensitive) and `cloudflare_r2_bucket.inngest_luks_header` with `count`, provider alias `cloudflare.r2`, `location = "WEUR"`, `prevent_destroy = true`, header comment copying the Chapter V wording of `workspaces-luks-header.tf` verbatim and stating "not a jurisdiction, never cite as EU residency". Variable comment: flipping back to `false` after a bucket exists plans a destroy blocked by `prevent_destroy`; disabling is not a supported route.
- 3.2 `apply-web-platform-infra.yml`: inert `-target=cloudflare_r2_bucket.inngest_luks_header` next to the sibling at ~line 576 (workflow byte budget: `wc -c` must stay under the 490,000 B gate in `workflow-file-size.test.ts`).
- 3.3 `scripts/encryption-posture-ledger.json`: row per `clo-wording.md` section 6; run `scripts/lint-encryption-posture.py`.
- 3.4 `inngest-luks-header.test.sh` modelled on `workspaces-luks-header.test.sh` (H1 to H12 guards): file-scoped exact cardinality (one bucket, zero `doppler_secret`, zero `random_*`), bucket name distinct from `soleur-terraform-state` and from both workspaces header buckets, the `count` gate present with default false, `prevent_destroy`, `WEUR` comment present and the string "EU residency" absent; register in the shard manifests and `infra-validation.yml`. Sweep other guard suites that list `.tf` resources: `git grep -ln 'workspaces_luks_header\|-target=' tests/ scripts/ plugins/soleur/test/ apps/web-platform/infra/`.
- 3.5 Legal and architecture records (CLO-gated, text in `clo-wording.md`): `knowledge-base/legal/article-30-register.md` PA-13 (e) conditional statement, (g)(15), conditional marker under (13); `knowledge-base/legal/compliance-posture.md` pointer; ADR-142 marker and addendum; ADR-282 edits and addendum; new ADR-297 (provisional ordinal, re-verify at ship); C4 edit (below); counsel-review audit `knowledge-base/legal/audits/2026-10-counsel-review-9927-header-backup.md` performed by the CLO agent on the final diff.
- 3.6 Runbook `knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md` section 5c: new subsection "Header backup: owner activation and recovery". Content (agent-run, owner-approved steps with command forms; no click-paths): (i) preconditions - window replace done and verified, P0 satisfied, CLO S1 to S5 recorded; (ii) mint a bucket-scoped write-only S3 credential via the Cloudflare API or the authenticated session, Playwright attempt first (`automation-status: UNVERIFIED - the activation change MUST run a Playwright attempt before any owner handoff`); prove PUT 200 and GET/LIST 403 by status code only; if unmintable STOP; (iii) write `INNGEST_LUKS_HDR_PUT` as `endpoint|bucket|key_id|secret` with output discarded, read back names only; ordering gate: strictly after the replace, because the live user_data must already admit the name; (iv) flip `inngest_luks_header_backup_enabled` in a reviewed PR - the merge apply creates the empty bucket; (v) first run: expect `backup=ok`, then record the first-upload date in ADR-282 and the register (second CLO attestation); (vi) recovery: the owner mints a read credential, restores with `luksHeaderRestore`, revokes the credential, records it; (vii) key-change gate: run the keeper and require `backup=ok` before and after any `luksChangeKey`; (viii) decommission: delete the object first, record, then retire the volume. State the residuals (write key can overwrite the single object; R2 unversioned; Terraform R2 token reach unknown).
- 3.7 Merge gate: only after the CLO attestation file exists with disposition DISCHARGED. The PR adds no carrier; confirm no tag is minted with `bash .github/scripts/mint-inngest-bootstrap-tag.sh --dry-run` after `git fetch --tags origin` (expect `result=noop`).

Apply: fires; the count gate makes the bucket plan to zero; expected plan = no change. No skip marker. Image: no.

### PR-D - "user_data byte plan" (cloud-init edit, LAST)

Edits to `cloud-init-inngest.yml`: (1) STAGED line: replace `inngest-luks-cutover.sh inngest-luks-cutover.service inngest-luks-cutover.timer` with `inngest-luks-keeper.sh inngest-luks-keeper.service inngest-luks-keeper.timer`; (2) quiesce loop: remove the cutover timer from the timer loop and from the stop line, the cutover service from the busy-check loop, and the `/var/lib/inngest-luks-cutover/frozen-active` busy line; remove the cutover timer from the service-status summary list; (3) delete the two lines that write and verify `/etc/default/inngest-luks-volumes` (only the retired cutover service read it) and update the adjacent comment; (4) append `|LUKS_HDR_PUT` to the `n_inngest` regex in the INNGEST_ group (keep `LUKS_CUTOVER` and `LUKS_ACTIVE_VOLUME_ID`; floor stays 6). Also: `inngest-userdata-budget.sh --min-headroom N` (default 0, distinct exit code for below-floor) plus a small semantics row in `inngest-host.test.sh`; `.github/workflows/infra-validation.yml` job `inngest-userdata-budget` passes 300 (sunset comment and tracked issue; basis runbook A1); `inngest-host.test.sh` STAGED membership assertions updated for the keeper trio; `cloud-init-inngest-provision-unit.test.sh` quiesce battery updated for the shorter loop; `plugins/soleur/test/cloud-init-user-data-size.test.ts` `INNGEST_GZIP_BUDGET` re-read (research found 32,300 below the measured 32,512; confirm whether that test is red on main before relying on it - do not fix a pre-existing red here, but record it).

Prerequisite: merge only after the bot pin-bump PR for the last image tag has merged and the zot mirror is healthy, so the pinned image no longer carries the cutover trio and does carry the keeper. State in the PR body that nobody may dispatch any host-replace until the promotion apply of #10951 is done (the prework dispatches nothing).

Apply: fires; `hcloud_server.inngest` is outside the merge `-target` set, so no replace is planned; the three Inngest resources already appear as expected drift (#10835, #10768) and must never be applied by a merge. Preflight rule per PR: read the plan; if anything beyond the expected set appears, stop. `[skip-web-platform-apply]` on its own line in a branch commit message is needed ONLY if that read shows unreviewed drift; none is expected.

## PR split and merge order

| Order | PR | Theme | Image release / pin bump | Fires merge apply | `[skip-web-platform-apply]` |
|---|---|---|---|---|---|
| 1 | PR-1 | flip-guard comment (b) + retire cutover trio (c) | Yes: carriers change, auto-mint tag N | Yes (infra path); plan expected no-op | Not needed |
| 2 | PR-2 | keeper trio (d) + uploader phase (e) + Better Stack alert | Yes: tag N+1 (merge directly after PR-1; the mint decides tag-vs-tip against the newest tag, so a second tag is expected) | Yes; plan = alert create only | Not needed |
| - | bot | pin-bump PR for the LAST tag (touches `cloud-init.yml`, `cloud-init-inngest.yml`) | merge only the last one; close the earlier bot PR unmerged (confirm in runbook "Bootstrap-image release" that a closed bot PR leaves no residue) | Yes (infra path) | Not needed |
| 3 | PR-3 | gated bucket, ledger, legal records, ADR-297, C4, runbook | No carrier (dry-run to confirm no tag) | Yes; count gate => no change | Not needed |
| 4 | PR-D | user_data byte plan + margin floor | No (cloud-init is rendered, not baked) | Yes; `hcloud_server.*` excluded | Not needed |

PR-3 may merge any time after PR-1/PR-2 once the CLO attestation is DISCHARGED; PR-D must follow the pin bump. Web-redeploy notice (#9755 text), to put in each PR body: "Merging a change under `apps/web-platform/infra/**` fires the production apply of the parent root and may redeploy the web platform. This change touches [Inngest host assets / Terraform for a disabled bucket / user_data] and plans no web-platform resource change; the apply outcome is verified after merge (provisioners succeeded, Better Stack via `scripts/betterstack-query.sh`, no SSH)." Post-merge verification of each PR is automated (apply run conclusion via `gh run list`, `git tag --contains <merge-sha> --list 'vinngest-v*'`, `bash apps/web-platform/infra/inngest-userdata-budget.sh`), not an owner checklist.

Image release steps (post-merge, all automated, no operator tag push): (1) after PR-1 and PR-2 merge, `gh run list --workflow mint-inngest-bootstrap-tag.yml` shows the mint runs; (2) `git tag --contains <merge-sha> --list 'vinngest-v*'` names the tag carrying each merge; (3) the bot pin-bump PR for the last tag appears; (4) confirm the zot mirror (not degraded; a `mirror_only` backfill dispatch exists if needed); (5) merge that bot PR only. If the mint or build fails at the credential or tag stage, the runbook recovery table applies - STOP and surface it; do not hand-push a tag (a hand-pushed tag starts nothing, ADR-232 A5).

## Window preconditions delta (additions to the 2026-10-23 package; owner-reserved acts stay owner-reserved)

- P0 (new): the #10951 ordering gate. No host-replace, provision-rehearsal or cutover dispatch between the #10951 merge and the promotion apply (`TF_VAR_inngest_config_digest` on `soleur/prd_terraform`, runbook `inngest-config-refresh.md` step 3, writes `doppler_secret.inngest_config_digest` into `soleur-inngest/prd`). That is a production Doppler write: owner-reserved, sequenced inside the window, not built here. A read-only names check for `INNGEST_CONFIG_DIGEST` precedes the replace dispatch. Floor 6 against a still-5-name live set fails the boot.
- P1: the pin in `cloud-init-inngest.yml` references an image that carries the keeper trio and no cutover trio (pin-bump PR merged, `git tag --contains`).
- P2: `bash apps/web-platform/infra/inngest-userdata-budget.sh --min-headroom 300` green on the trial merge of PR-D.
- Window order: promotion apply, names check, replace, then (strictly after) the `INNGEST_LUKS_HDR_PUT` write, then verification. The keeper's first row appears within about 10 minutes of boot (`OnBootSec=10min`): add it to the post-replace read-only checks (`probe=ok`, `backup=unconfigured` until activation).

## Infrastructure (IaC)

### Terraform changes

- New `apps/web-platform/infra/inngest-luks-header.tf`: `cloudflare_r2_bucket.inngest_luks_header` (provider `cloudflare.r2`, existing alias in `main.tf`, token `var.cf_api_token_r2` already provisioned for the siblings), `count`-gated by a non-sensitive bool with default `false`. No `doppler_secret`, no `random_*`, no new sensitive variable (so `hr-tf-variable-no-operator-mint-default` and the no-default-variable sharp edge are not engaged).
- `apply-web-platform-infra.yml`: one inert `-target` line.
- `betterstack-logs-alerts.tf`: one alert (PR-2).
- Required providers and pins unchanged (cloudflare 4.52.7, `~> 4.0`).
- Sensitive values: none enter Terraform; the S3 key pair is minted by the owner at activation and held only in the Doppler secret `INNGEST_LUKS_HDR_PUT` (not derivable from any Cloudflare API token field - learning `2026-05-18-cla-evidence-r2-s3-creds-not-derived.md`).

### Apply path

(a) cloud-init-only for all host-side changes: they reach the host only through the next approved replace (image pin plus rendered user_data). No in-place edit, no SSH. Expected downtime and blast radius of THIS work: none (no host is touched). The window's own downtime (scheduler dark 15 to 60 minutes plus approval latency) is unchanged and not authorized here.

### Host fan-out

`terraform_data` SSH provisioners: none added or edited. The Inngest host is a single host; web hosts are untouched. Fleet siblings: not applicable.

### Distinctness / drift safeguards

Bucket name distinct from `soleur-terraform-state` and from both workspaces header buckets (asserted by the new test); the count gate keeps the scheduled drift job at zero planned changes while off; the identity regex keeps `LUKS_CUTOVER` and `LUKS_ACTIVE_VOLUME_ID` admitted so the live Doppler config cannot brick a boot; `lifecycle.prevent_destroy` on the bucket.

### Vendor-tier reality check

R2: write-only bucket-scoped S3 credential availability is unverified (the vendor console may offer only read-write or read-only); the uploader refuses a readable key and the activation step stops if write-only cannot be minted. R2 cost is small and unquantified (one object of about 16 MiB overwritten at most daily; operations pricing applies) - an owner money item (D12). The Better Stack alert follows the paid-tier gating of its siblings.

## Observability

```yaml
liveness_signal:
  what: "SOLEUR_INNGEST_LUKS_KEEPER row (probe=ok|fail, backup=unconfigured|unchanged|ok|refused|fail) shipped by Vector to the Better Stack source soleur-inngest-vector-prd"
  cadence: "10 minutes after boot, then daily at 03:17 UTC with up to 30 minutes randomized delay"
  alert_target: "Better Stack logtail_exploration_alert on probe=fail or backup=fail|refused, routed to the existing operator email policy; a missing daily row is read by the follow-up dead-man issue (D13) and, until then, by the post-replace read-only check"
  configured_in: "apps/web-platform/infra/inngest-luks-keeper.timer and betterstack-logs-alerts.tf"
error_reporting:
  destination: "Better Stack Logs (layer 3, Vector journald shipper) via the keeper SyslogIdentifier; the unit-exit row from ExecStopPost carries the exit code"
  fail_loud: "probe=fail exits 1 (unit failed); backup=refused reason=credential_readable and backup=fail reason=<closed token> emit a row and exit 1; backup=unconfigured exits 0"
failure_modes:
  - mode: "Doppler passphrase no longer opens the device (overwritten key, wrong volume)"
    detection: "layer 3: row probe=fail reason=passphrase; Better Stack exploration alert"
    alert_route: "operator email via the Better Stack policy"
  - mode: "header upload fails or credential rejected"
    detection: "layer 3: row backup=fail reason=<closed token>"
    alert_route: "operator email via the Better Stack policy"
  - mode: "write credential can read (not write-only)"
    detection: "layer 3: row backup=refused reason=credential_readable; nothing uploaded"
    alert_route: "operator email via the Better Stack policy"
  - mode: "keeper not installed on the replaced host (image or STAGED mismatch)"
    detection: "layer 3: phone-home stage luks-keeper-install-MISSING from the bootstrap; absence of the first-boot keeper row inside 15 minutes in the post-replace read-only check"
    alert_route: "post-replace verification (window runbook steps 8 to 10) and the existing boot-stage alerts"
  - mode: "user_data margin regresses below 300 B before the window"
    detection: "layer 6: workflow-run log of the required infra-validation job inngest-userdata-budget (below-floor exit code distinct from over-cap and from unmeasurable)"
    alert_route: "required check fails the PR"
logs:
  where: "Better Stack source soleur-inngest-vector-prd (SYSLOG_IDENTIFIER of the keeper); journald on the host is not a primary read path"
  retention: "90 days (betterstack-log-query.md, measured 2026-09-04)"
discoverability_test:
  command: grep -l SOLEUR_INNGEST_LUKS_KEEPER apps/web-platform/infra/inngest-luks-keeper.sh apps/web-platform/infra/vector.toml
  expected_output: inngest-luks-keeper.sh
  credentials_required: "Better Stack ClickHouse read connection (Doppler soleur/prd_terraform BETTERSTACK_QUERY_*) - there is no unauthenticated substitute for reading a host-emitted row; the property-level check is the post-replace read-only query in the window runbook"
```

ing">(The local probe above proves the keeper script emits the row marker and the shipper config names it, without credentials or SSH; the credential-gated query that reads the live keeper row is declared under `credentials_required` and is part of the window verification, per `hr-no-dashboard-eyeball-pull-data-yourself`.)

## Encryption Posture

```yaml
at_rest:
  - store: cloudflare_r2_bucket.inngest_luks_header
    mechanism: provider-managed:Cloudflare-R2-SOC2-Type-II
    evidence: "Cloudflare R2 encrypts objects at rest with AES-256-GCM (developers.cloudflare.com/r2/reference/data-security/); Cloudflare holds an AICPA SOC 2 Type II attestation with R2 in scope (Trust Hub); re-read and dated at build time"
    defends_against: "physical-media compromise of the header copy in Cloudflare's infrastructure; as a recovery path only, corruption or overwrite of the LUKS header while volume and passphrase are intact"
    does_not_defend: "a read-capable credential combined with the passphrase and the volume; overwrite or deletion by any reader of the write-only credential or by the Terraform R2 token; a stale copy between a key change and the next upload; loss of the volume or both passphrase copies (Art. 32(1)(c) NOT provided); the Chapter V position"
    disclosed_as: not-publicly-claimed
    live_verification: "unavailable: declared and gated off; no object exists; the first successful upload record is the planned measurement"
in_transit:
  - connection: "dedicated Inngest host -> Cloudflare R2 S3 endpoint (header PUT)"
    enforced_at: "apps/web-platform/infra/inngest-luks-keeper.sh (endpoint regex check and curl --aws-sigv4 over https)"
    tls: "https, TLS 1.2+ (curl default; the endpoint regex forbids http)"
    cert_verification: on
    does_not_defend: "a compromised host or Doppler boot token reading the write-only credential"
    disclosed_as: not-publicly-claimed
```

The existing store `hcloud_volume.inngest_redis_luks` keeps its ledger row (mechanism luks); this change alters no row except the wording that said the header has no off-host copy (ADR/register text, conditional on activation).

## Guard Contract

### Guard 1 - user_data margin floor (`inngest-userdata-budget.sh --min-headroom`)

**Property.** No tree that merges to main has less than the configured number of bytes between the stored user_data payload and Hetzner's 32,768 B cap once the floor is enabled.

**Assembly.** Chokepoint: the single render chain `local.inngest_user_data_plain` -> `base64gzip` in `inngest-host.tf`, measured by the budget script (which already fails closed on an unwired chain), invoked by exactly one required CI job (`inngest-userdata-budget` in `infra-validation.yml`) and by the window preflight. Members that drift: the floor constant, the job's argument, the below-floor exit code. All callers (CI job, window preflight, the semantics row in `inngest-host.test.sh`) must pass the same value; the test greps the workflow argument rather than restating the number.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add 200 B of non-comment payload to `cloud-init-inngest.yml` so headroom drops below 300 B | RED (distinct below-floor exit) |
| 2 | Remove the `--min-headroom` argument from the workflow job (guard's own dispatch) | RED (the semantics row asserts the job passes a value >= 300) |
| 3 | Make an unmeasurable render fold into a pass: delete the strip declaration | RED (exit 2 preserved, not folded into pass) |
| 4 | Set the floor argument to 0 after a compliant 300 | RED (workflow-argument grep) |
| 5 | A second consumer: a new job step invoking the script without the flag | RED (the test enumerates every invocation of the script in `.github/workflows/`) |

**Harness rows.** RED: edit the semantics row to compare with `-ge` instead of `-gt` at headroom exactly 300 (must stay PASS at exactly 300 and RED at 299); must-PASS non-canonical: a render at 301 B and at exactly 300 B (not only the canonical 364 B). **Anchor.** The 300 value's source is runbook A1 prose; a stored value in the workflow can be edited with the tree it protects, so the anchor is the CODEOWNERS-routed review of `infra-validation.yml` plus the runbook citation in the sunset comment; the floor proves consistency, not integrity, and the plan says so.

### Guard 2 - the keeper's write-only proof and endpoint check

**Property.** The keeper never uploads the header with a credential that can read, and never to an endpoint outside the R2 S3 shape.

**Assembly.** Chokepoint: the single upload function in `inngest-luks-keeper.sh`, reached from the only code path that calls `curl` with the credential; the readability GET and the endpoint regex both sit before it. The test enumerates every `curl` invocation in the script and asserts each is dominated by the check (census with a red "unclassified" bucket).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Stub `curl` GET of the nonexistent key to return 200 (readable key) | `backup=refused reason=credential_readable`, zero PUT, exit 1 |
| 2 | Stub the GET to return 404 | PUT occurs (the compliant path is not over-blocked) |
| 3 | Set the endpoint to `http://...` or a non-R2 host | refused, zero network call |
| 4 | Remove the readability check from the script (guard's own dispatch) | suite RED (a census row counts curl calls not dominated by the check) |
| 5 | Add a second `curl` call after a compliant first (a "retry" PUT without the check) | suite RED |
| 6 | Header marker equals stored hash / marker differs | `backup=unchanged`, zero PUT / one PUT |

**Harness rows.** RED: make the stub `curl` ignore its arguments - the suite must fail because it asserts the argv (method, URL, `--aws-sigv4`, no `-k`); must-PASS non-canonical: an endpoint in the `.eu.` form, and a secret containing an extra `|` is rejected cleanly (field-count check). **Anchor.** Local proofs only; the live write-only proof is S1 of the CLO stop conditions (status codes recorded before the secret is written).

### Guard 3 - cutover vocabulary absent from the image

**Property.** No image-baked carrier names the retired plaintext volume, the staging mapper, or the staging mount.

**Assembly.** The set of `cp` source files in `build-inngest-bootstrap-image.yml` (the same set the mint script derives carriers from) plus `inngest-config-refresh-set.txt` members. The test derives the set from the workflow rather than listing names, greps each for `PLAIN_ID`, `inngest-redis-staging`, `/mnt/data-luks`, `INNGEST_LUKS_PLAIN_VOLUME_ID`, and asserts the removed trio is absent from the workflow, `inngest-bootstrap.sh` and STAGED.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Re-add `PLAIN_ID=` to any carrier | RED |
| 2 | Re-add `inngest-luks-cutover.sh` to the refresh set | RED |
| 3 | Add a new carrier `cp` line whose file contains `/mnt/data-luks` (second member after a compliant first) | RED |
| 4 | Empty the derived carrier set (guard's own dispatch: "0 checked") | RED (floor on the carrier count) |

**Harness rows.** RED: rename the sentinel token in the test; must-PASS: a carrier containing the word "plaintext" in an unrelated comment is allowed (the match is on the exact retired identifiers). **Anchor.** Merge-base diff of the refresh set and workflow by CODEOWNERS-routed review.

## Architecture Decision (ADR/C4)

### ADR

- Create ADR-297 (provisional ordinal: highest on the worktree and on `origin/*` refs is 296; re-verify across all pushed refs immediately before merge and after any sync): "On-host LUKS keeper: key-continuity probe and gated header-only backup; retirement of the additive-cutover FSM". Decision: one combined keeper trio; one owner-written secret `INNGEST_LUKS_HDR_PUT`; exact-name admission in the boot identity check; technical write-only proof; count-gated bucket default off. Alternatives considered: stub cutover script, two trios, Terraform-owned `doppler_secret`, prefix wildcard admission, hidden-from-merge-apply (H), ungated declaration (I).
- Amend ADR-142 (supersede marker and 2026-10-24 addendum; note the retirement of the cutover trio) and ADR-282 (edits and addendum) with the CLO text verbatim from `clo-wording.md`.

### C4 views

Read all three model files (`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`). Checked and already modelled: external human actor (the founder/owner actor exists); external systems (Cloudflare system carries R2; Doppler; Better Stack; Hetzner); container `inngestRedis` (its description currently says the ciphertext and the LUKS header have no backup); relationship `hetzner -> cloudflare` (workspaces header upload) exists. Not modelled: an `inngest -> cloudflare` edge for the gated header upload, and the `inngestRedis` residual sentence becomes conditionally false at activation. Tasks: add an `inngest -> cloudflare` edge ("GATED OFF: uploads the LUKS header only, write-only credential, current header only; no copy until the first recorded upload; Art. 32(1)(c) not provided", technology "HTTPS S3 PUT") - `cloudflare` and `inngest` are already included in the context and containers views, so it renders; amend the `inngestRedis` description to say the header backup is declared and gated off and the ciphertext still has no backup; update cutover-FSM wording if present. Run `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts` and `plugins/soleur/test/c4-count-parity.test.sh` (edge prose may embed derived counts).

### Sequencing

ADR-297 is authored now describing the target state with "status: adopting"; it flips to accepted at the first recorded upload (second CLO attestation). Legal markers are all conditional on activation, so they can merge before activation without being false.

## Domain Review

**Domains relevant:** Engineering, Legal, Operations

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Ruled D1 to D6, D9, D10, D13 (2026-10-24). Corrections to the premise: the cutover script rides the signed refresh channel too; the parity test does not demand a `-target` per resource; the boot identity check is exact-set; image-first-cloud-init-second is safe in every order (only `install_missing` noise).

### Legal (CLO)

**Status:** reviewed
**Assessment:** Header-only backup permitted; write-only credential and bucket coordinates may ride `soleur-inngest/prd`; no read-capable credential stored anywhere; "EU" must not be written for a default-jurisdiction bucket; Art. 32(1)(c) remains NOT provided in every record; counsel-review audit required before PR-3 merges (`2026-10-counsel-review-9927-header-backup.md`). Wording in `clo-wording.md`. `soleur:gdpr-gate` runs on the PR-3 diff at work time (advisory); the CLO ruling is the plan-time compliance gate.

### Operations

**Status:** reviewed (planner)
**Assessment:** R2 header bucket cost is an owner money item at activation (D12); no vendor signup is introduced; activation is a runbook entry with an automation attempt first.

### Product/UX Gate

**Tier:** none - no UI surface file in Files to Create or Edit (no `components/**`, `app/**`).
**Decision:** N/A. **Pencil available:** N/A (no UI surface).

## Open Code-Review Overlap

- #10112 (`inngest-luks-cutover.sh`, `cloud-init-inngest.yml`, ledger, ADR-142): Fold in - PR-1 implements item 1 of #10112; items 2 to 4 stay (rehearsal volume is out of scope per the operator's exclusion; blank-prd DR and duplicated reopen arms need user_data bytes this window does not have). PR bodies use `Ref #10112`, not a closing keyword.
- #10243 (nft comment correction in `cloud-init-inngest.yml`): Acknowledge - comment-only, not folded in (PR-D touches the file for unrelated lines; folding it widens review scope for no byte benefit).

## Files to Edit

- `apps/web-platform/infra/inngest-server-flip-guard.sh` (comment)
- `apps/web-platform/infra/inngest-bootstrap.sh` (delete cutover install and enable blocks; add keeper block)
- `apps/web-platform/infra/inngest-config-refresh-set.txt` (drop member)
- `.github/workflows/build-inngest-bootstrap-image.yml`, `.github/scripts/check-inngest-bootstrap-build.sh`, `.github/workflows/check-inngest-bootstrap-build.yml`, `.github/workflows/build-inngest-config-bundle.yml` (member-count text), `.github/workflows/infra-validation.yml` (new suites, margin floor), `.github/workflows/apply-web-platform-infra.yml` (inert `-target`)
- `apps/web-platform/infra/cloud-init-inngest.yml` (PR-D only)
- `apps/web-platform/infra/inngest-userdata-budget.sh` (`--min-headroom`)
- `apps/web-platform/infra/vector.toml`, `betterstack-logs-alerts.tf`
- Tests and registries: `inngest.test.sh`, `inngest-host.test.sh`, `cloud-init-inngest-provision-unit.test.sh`, `cloud-init-inngest-bootstrap.test.sh`, `inngest-luks-sole-copy.test.sh`, `inngest-redis-luks.test.sh`, `inngest-redis-luks-import-rehearsal.test.sh`, `inngest-config-refresh.test.sh`, `inngest-config-bundle-pack.test.sh`, `ci-deploy.test.sh`, `journald-config.test.sh`, `suite-shard-legs.tsv` (apps/web-platform/infra and scripts copies), `suite-durations.tsv`, `scripts/ci-pr-affected-audit.baseline.tsv`, `scripts/lib/test-affected-paths.sh`, `scripts/lib/inngest-probe-row.test.sh`, `scripts/guard-vacuity-floor.test.sh`, `.claude/hooks/grep-q-pipe-guard.test.sh`, `plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts`, `plugins/soleur/test/sole-copy-drift-check.test.sh`, `plugins/soleur/test/cloud-init-user-data-size.test.ts` (read only unless red), `apps/web-platform/test/infra/betterstack-send-failed-alert.test.sh`, `apps/web-platform/test/infra/inngest-luks-wrong-volume-alert.test.sh`, `plugins/soleur/test/inngest-config-bundle-mirror.test.sh`
- `scripts/encryption-posture-ledger.json`
- `knowledge-base/legal/article-30-register.md`, `knowledge-base/legal/compliance-posture.md`
- `knowledge-base/engineering/architecture/decisions/ADR-142-inngest-redis-aof-zero-data-loss-luks-migration.md`, `ADR-282-sole-copy-luks-volume-protection-set.md`
- `knowledge-base/engineering/architecture/diagrams/model.c4` (and `views.c4` only if the edge needs an include)
- `knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md`, `inngest-server.md` (window preconditions and cutover-retirement notes)

Never edit: migration 163; draft PR #10692 and its worktree; PR #10936's worktree; the live host.

## Files to Create

- `apps/web-platform/infra/inngest-luks-keeper.sh`, `inngest-luks-keeper.service`, `inngest-luks-keeper.timer`, `inngest-luks-keeper.test.sh`
- `apps/web-platform/infra/inngest-luks-header.tf`, `inngest-luks-header.test.sh`
- `knowledge-base/engineering/architecture/decisions/ADR-297-<slug>.md` (ordinal provisional)
- `knowledge-base/legal/audits/2026-10-counsel-review-9927-header-backup.md` (written by the CLO agent at PR-3 time)

Deleted: `inngest-luks-cutover.sh`, `inngest-luks-cutover.service`, `inngest-luks-cutover.timer`, `inngest-luks-cutover.test.sh`.

Path-glob verification: the mint workflow `paths:` globs (`apps/web-platform/infra/inngest*`) match every new file name above (checked by name; re-run `git ls-files | grep` at work time).

## Follow-up issues to file (deferral tracking; milestone from `knowledge-base/product/roadmap.md`, default Post-MVP / Later)

1. Retire dispatcher `op=luks-cutover` (workflow, `scripts/cutover-inngest.sh`, runbook, tests) - already inert.
2. Dead-man heartbeat for the keeper (needs another admitted secret name).
3. Jurisdiction-pin the Inngest header bucket (provider v5 bump or owner adoption of an eu bucket).
4. Remove stale cutover tags from `vector.toml`; drop the two cutover names from the identity regex (needs a Doppler secret deletion, owner-authorized).
5. Relax or ratchet the 300 B floor after the window (sunset).

Each issue body carries `Ref #9927` or `Ref #10112`, never a closing keyword.

## Acceptance Criteria

### Pre-merge (per PR)

#### Functional Requirements

- [ ] PR-1: `git grep -n 'PLAIN_ID\|inngest-redis-staging\|/mnt/data-luks\|INNGEST_LUKS_PLAIN_VOLUME_ID' -- 'apps/web-platform/infra/inngest-*.sh' 'apps/web-platform/infra/*.service' 'apps/web-platform/infra/*.timer'` returns nothing; the three cutover files and the cutover test are deleted; the refresh set lists four members and every assertion and message that said five is updated.
- [ ] PR-1: the flip-guard comment states the 90-day retention with its date basis; `bash apps/web-platform/infra/inngest-server-flip-guard.test.sh` passes.
- [ ] PR-2: `inngest-luks-keeper.test.sh` passes with stubs and, where root and loop devices exist, against a loopback LUKS device; no test touches a production device or any credentialed service.
- [ ] PR-2: the keeper rows, alert, vector tag and shard registrations exist; `scripts/lint-encryption-posture.py` passes.
- [ ] PR-3: `terraform fmt -check` and an offline `terraform validate` pass; the new test proves the bucket is count-gated with default `false`, no `doppler_secret`/`random_*` exists in the file, the bucket name is distinct from the tfstate and workspaces header buckets, and the string "EU residency" is absent.
- [ ] PR-3: ledger row, Art. 30 markers, ADR-142/282 markers, ADR-297, C4 edit, runbook entry present; every legal sentence matches `clo-wording.md`; `knowledge-base/legal/audits/2026-10-counsel-review-9927-header-backup.md` exists with disposition DISCHARGED before merge.
- [ ] PR-D: `bash apps/web-platform/infra/inngest-userdata-budget.sh --min-headroom 300` exits 0 on the final tree and reports headroom >= 350 B (planner measurement 364 B); `LUKS_CUTOVER` and `LUKS_ACTIVE_VOLUME_ID` remain in the identity regex; floor still 6.
- [ ] Every PR body: ends with the generated-with line, uses `Ref #9927` / `Ref #10112` / `Ref #10390` only, carries the web-redeploy notice paragraph, and names the apply expectation. No commit adds `[skip-web-platform-apply]` unless the preflight plan read shows unreviewed drift.

#### Non-Functional Requirements

- [ ] No change makes a `terraform plan` of the merge `-target` set include `hcloud_server.*`, a create of the bucket, or any Doppler write (read the plan before each merge).
- [ ] Observability block satisfied: keeper rows reach Better Stack without SSH.
- [ ] NFR register assessed (`soleur:architecture assess` against `nfr-register.md`).

#### Quality Gates

- [ ] Guard 1 to 3 mutation rows each demonstrated RED once at work time (recorded in the PR body).
- [ ] Affected tests only from work; the full battery is a ship-phase concern, not run by spawned agents.
- [ ] `plugins/soleur/test/terraform-target-parity.test.ts`, `workflow-file-size.test.ts` and the C4 tests pass.

### Post-merge (automated, no operator checklist)

- [ ] After PR-1 and PR-2: `git tag --contains <merge-sha> --list 'vinngest-v*'` names the tag; `gh run list --workflow build-inngest-bootstrap-image.yml` shows success for the last tag; the zot mirror is not degraded; the bot pin-bump PR for the LAST tag is merged and earlier ones closed.
- [ ] After PR-D: the apply run for the merge sha concluded success with no host replace planned; `inngest-userdata-budget.sh --min-headroom 300` green on main.
- [ ] Owner-reserved, NOT done by this work: any replace dispatch, the promotion apply (P0), the credential mint, the `INNGEST_LUKS_HDR_PUT` write, flipping the bucket variable, `op=resume`, #10382. Each is stated as the owner's later step in the runbook entry and in the window preconditions, with the owner's go as the trigger.

## Test Scenarios

(layer in brackets; prefer unit/integration; no e2e)

- Given a stubbed `cryptsetup` that accepts the passphrase, when the keeper runs, then it emits `probe=ok` and exits 0 [unit].
- Given a stub that rejects the passphrase, then `probe=fail reason=passphrase`, exit 1, and no destructive command was invoked [unit].
- Given `isLuks` returns rc 1 for an unreadable device, then the keeper does not branch to any format path (rc and stderr are classified separately) [unit].
- Given no `INNGEST_LUKS_HDR_PUT`, then `backup=unconfigured`, exit 0, zero `curl` calls [unit].
- Given a readable credential (stub GET returns 200), then `backup=refused reason=credential_readable`, zero PUT [unit].
- Given a write-only credential (stub GET 403/404 per the R2 shape) and a changed header hash, then exactly one PUT to the fixed object key with `--aws-sigv4`, marker updated, `backup=ok` [unit].
- Given an unchanged header hash, then `backup=unchanged`, zero PUT [unit].
- Given a malformed secret (wrong field count, `http://` endpoint, non-R2 host), then refused with no network call [unit].
- Given a real loopback LUKS device and a real `luksHeaderBackup`, the produced file restores with `luksHeaderRestore` onto a second loopback device and the passphrase opens it [integration].
- Given the final tree, the budget script reports >= 350 B and `--min-headroom 300` exits 0; given +200 B of payload it exits with the below-floor code [integration].
- Given the carriers derived from the build workflow, none contains the retired vocabulary [unit].
- Given the bootstrap tests, a staged keeper trio installs; a missing trio logs `install_missing` and leaves the block without failing the boot [unit].
- Given the Terraform file, an offline `terraform validate` passes and a plan with the default variable value has zero resources for the file [integration, offline with the plugin cache].

## Dependencies & Risks

- Risk: PR-D before the pin bump leaves a replaced host with a keeper STAGED name the pinned image lacks (only `install_missing` noise, but the keeper would be absent). Mitigation: merge order; PR-D body states the dependency; P1 precondition.
- Risk: the host `curl` is older than 7.75 (`--aws-sigv4` missing). Mitigation: verify in PR-2 before ready; if older, stop and re-rule with the CTO.
- Risk: the refresh set loses a member while a bundle build or the verify-fix arc (#10390 defect 3) is in flight. Mitigation: no bundle is built by this work; the pack and mirror tests are updated in the same PR; the live host keeps its installed copies until the replace.
- Risk: a later `soleur-inngest/prd` secret added by anyone without a regex edit bricks the next boot. Mitigation: unchanged exact-set design; D5 refuses the wildcard.
- Risk: R2 cannot mint a write-only key. Mitigation: stop at activation; the uploader refuses a readable key.
- Risk: `INNGEST_GZIP_BUDGET` in `cloud-init-user-data-size.test.ts` reads 32,300 against the measured 32,512; if red on main it is a pre-existing red, record and do not fix here (known main-wide reds #6480, #10448 also not fixed here).
- Rollback: PR-1/PR-2 are reverted by revert PRs (the image tags remain; a newer pin can point back); PR-3 is inert while the variable is false; PR-D is reverted by a revert PR. No host state is touched by any of them.

## References & Research

#9927, #10112, #10390, #9755, #6890, #10081 (merged), #10951, #10835, #10768, #8408 (precedent), #8285 (retired backstop), #10382 (not in scope). Files: `luks-monitor.sh` (probe precedent), `workspaces-luks-header.tf` (bucket precedent), `inngest-userdata-budget.sh`, ADR-232 (image release), ADR-135 (refresh channel), ADR-282, ADR-142, ADR-119. Specs: `decision-challenges.md`, `clo-wording.md`, `tasks.md` in `knowledge-base/project/specs/feat-one-shot-inngest-window-prework/`.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan fills it; keep it filled.
- Do not edit `inngest-luks-cutover.sh` on main before the deletion lands: it is a signed-refresh-set member and an edit would ship to the live host through the bundle path.
- Do not drop `LUKS_CUTOVER` or `LUKS_ACTIVE_VOLUME_ID` from the identity regex: both names exist in the live config.
- Do not add a `doppler_secret` for the header in Terraform: each name needs a regex edit and tfstate would hold values.
- A `-target` for a count-gated resource is inert while off; the parity test checks only SSH-provisioned `terraform_data`, so do not rely on it to catch a missing target (derive the list with `git grep -n 'workspaces_luks_header' .github plugins tests scripts`).
- Intermediate margin figures are measured pairs from scratch copies; the final 364 B is the only direct measurement of the full set. Re-measure on the real branch after the last edit.
- Runbook text derived from this plan must not contain the patterns the infra-plan write guard denies (operator-run SSH, secret-set commands, service state-change commands in prose, vendor click-paths); describe steps as agent-run and owner-approved, with API or Playwright attempts first.
