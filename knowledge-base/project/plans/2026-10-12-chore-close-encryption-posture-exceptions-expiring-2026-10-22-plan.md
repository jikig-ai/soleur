---
title: "chore: close the encryption-posture exceptions expiring 2026-10-22"
date: 2026-10-12
slug: close-encryption-posture-exceptions-expiring-2026-10-22
branch: feat-one-shot-encryption-posture-exceptions-2026-10-22
issue: 6897
lane: cross-domain
type: chore
requires_cpo_signoff: false
---

## Enhancement Summary

**Deepened on:** 2026-10-12 (headless). **Passes run:** Phase 4.6 (User-Brand Impact present, threshold `aggregate pattern`), 4.7 (Observability: all five fields present, command starts with allowlisted `python3`, finishes in about a second, `expected_output` is the literal `PASS`), 4.8 (no PAT-shaped variables), 4.10 (Encryption Posture present, every `does_not_defend` non-empty, every exception carries tracker and date), 4.11 (`python3 scripts/lint-guard-contract.py` exit 0, 1 entry), 4.12 (exactly one unfenced `## Scope Check`, all three subsections). No halt fired. Rule IDs cited: none. Live checks re-run: lint baseline PASS; `plugins/soleur/test/c4-count-parity.test.sh` ALL TESTS PASSED; ADR-068, ADR-142, ADR-198, ADR-220 and ADR-239 files exist.

**Added by deepen:**
- `knowledge-base/legal/article-30-register.md` was grepped for a session-Redis or replay-buffer entry (CLO ruling d): none, so removing the ledger row needs no register edit.
- Serving path (CLO open item): web-1 `luks-monitor` row 2026-10-12T12:28Z reports `/mnt/data is LUKS-backed (mount_source=/dev/mapper/workspaces)` with `workspace_count=9`; with `git_data_store=disabled`, workspaces are served from that volume, not from the git-data host, so the published "serving volume is LUKS-encrypted" wording is not contradicted for web-1. No statement about web-2.
- PR2 design correction (from review): the post-apply volume loop is inline, `GATE_MODE` is not in scope there, and the replace shape of the LUKS volume is already enforced by the pre-apply rotate gate (`tests/scripts/lib/git-data-host-replace-gate.sh`, rotate arm R1-R2). PR2 therefore extracts the loop, passes `APPLY_TARGET`, and carries a three-row matrix.
- Attribution checks: the wipe body deletion in #8189 is stated in ADR-239 and the #8211 body; the 2026-10-11 rotate run is 38140050880 (job `git_data_host_replace`, step `Terraform apply … both-volumes-preserved assert` failed on `hcloud_volume.git_data_luks shows 1 delete/forget action(s)`).

**Open items carried to work time (none needs the operator unless stated):** re-measure the Hetzner and Better Stack facts the day PR1 is written; create the in-transit tracker issue before editing the three rows; any wipe, any `git-data-host-rotate` re-dispatch and the 2026-10-24 CLO final re-ruling are operator or CLO actions, not part of either PR.

## Overview

Six rows in `scripts/encryption-posture-ledger.json` carry `expires_on: 2026-10-22`. On 2026-10-23 the lint fails every pull request. Three are store rows (`redis.session_store`, `git_data.baked_credentials_on_host`, `hcloud_volume.git_data`); three are in-transit rows (two zot links, one Inngest link) that share the tracking issue #6897. This plan measures each row against live state, then converts, re-points or renews it with a justification that is true today. Nothing is renewed only to turn the lint green.

Planning-phase constraint: this plan edits no ledger, source or workflow file. All edits below happen at work time. No dispatch, `terraform apply`, Doppler write, volume wipe or destroy is part of this plan; any of those needs the operator's go-ahead naming the command.

## Research Reconciliation — Spec vs. Codebase

| Claim in the ask | Reality (verified 2026-10-12) | Plan response |
|---|---|---|
| "Main reports 22 stores, 10 connections, 0 failing" | Reproduced from this worktree: `22 stores, 10 connections, 0 unledgered, 0 failing checks -> PASS`, plus six expiry warnings (3 stores, 3 connections). | Baseline recorded; the same command is the final gate. |
| "No Terraform for the session-store host found; if managed Redis or on the web host, say so" | It is neither. There is no session-store host at all. Hetzner lists exactly 5 servers and 6 volumes, none a session Redis. `apps/web-platform/package.json` and the lockfile carry no Redis client. `server/stream-replay-buffer.ts` is an in-memory per-process ring buffer. ADR-068 places the session Redis in Phase 4a (post-GA, unbuilt); `model.c4` `sessionStore` is a design element. Better Stack 7-day search for session-redis returns nothing. | The row describes a store that does not exist. Delete it (CTO ruling A), not "measure then convert". |
| "The tracking issue on git_data.baked_credentials_on_host is CLOSED" | Confirmed: #7772 closed 2026-09-04. The lint only checks `^#\d+$`, not open state. | Re-point to open #8620 (CTO ruling B). Add an explicit open-state check to the acceptance criteria. |
| "#6897 last comment says git_data is untouched" | True, but the git-data host has since been replaced: server 169724272 created 2026-10-11T12:50:15Z by rotate run 38140050880; it carries both the new LUKS volume 107102614 and the plaintext volume 106867358. | Row text and `live_verification` record the 2026-10-11 birth. |
| "Find how far the git-data rotate and flag flip have got" | Rotate: applied 2026-10-11 but the job concluded `failure` (post-apply assert bug, see Research Insights). Flip: not done, `git_data_store=disabled` on every web container today. D6 stamp: cannot exist while the assert bug stands. Wipe body: does not exist on main (deleted in #8189). | Renew `hcloud_volume.git_data` on a short horizon (CLO), fix the assert in a separate PR (CTO ruling C-ii), no wipe. |
| "Do not claim emptiness for web-2; the ledger has no live host check for web-2" | Honoured. This plan makes no web-2 claim. (Incidental: a `luks-monitor` OK row from `soleur-web-2` exists at 2026-10-12 00:28Z; it is not used as evidence here.) | No web-2 statement in any row or comment. |

## Research Insights

**Premise Validation.** Checked by reference: #6897, #7992, #8211, #9572, #7456 (all OPEN), #7772 (CLOSED), #8620 (OPEN), #6167 (OPEN), #8285 (CLOSED), #5274 (OPEN), #6931 (CLOSED), #8209/#8609/#8573 (OPEN), #9262/#9438 (CLOSED). Cited paths confirmed on the branch (identical to origin/main at HEAD): ledger, lint, `git-data.tf`, `git-data-luks.tf`, `cloud-init-git-data.yml`, `git-data-cutover.yml`, `apply-web-platform-infra.yml`, ADR-239, ADR-068, the audit doc, `model.c4`. Stale premise found: "measure the session-store host posture" presumes a host. Mechanism check against the ADR corpus: ADR-068 line ~504 chose a self-hosted EU session Redis for Phase 4a and ADR-239 "Retention end for the plaintext volume" already states the re-open rule this plan follows ("the date is not extended quietly"). No cited mechanism sits in a rejected-alternatives table.

**Measurements (read-only; Hetzner API with `HCLOUD_TOKEN_READONLY`, Better Stack via `scripts/betterstack-query.sh`; no SSH):**

| Fact | Value | Source |
|---|---|---|
| Servers | web-platform 123931471, web-2 169271252 (2026-10-07), inngest 169426216 (2026-10-08), git-data 169724272 (2026-10-11), registry 169742393 (2026-10-11) | Hetzner `GET /servers` |
| Volumes | git-data-luks-store 107102614 (2026-10-11, server 169724272); git-data-store 106867358 (plaintext ext4, created 2026-09-14, server 169724272, delete protection false); web-platform-data-luks 106443278 (web-1, protected); registry-store 106585109; web-platform-data-web-2 107059048; inngest-redis-store-luks 106903269 (protected) | Hetzner `GET /volumes` |
| Session-store host/volume | none | same |
| Flag | `git_data_store=disabled` on all three web container hostnames sampled, latest 2026-10-12 | Better Stack |
| Serving path today | web-1 `luks-monitor`: `/mnt/data is LUKS-backed (mount_source=/dev/mapper/workspaces)`, `workspace_count=9`, 2026-10-12T12:28Z | Better Stack (answers the CLO open item) |
| Rotate | run 38140050880 (2026-10-11T12:38Z, `git_data_host_replace` job, rotate confirm token step success): `Terraform apply … both-volumes-preserved assert` failed with `hcloud_volume.git_data_luks shows 1 delete/forget action(s)`; boot poll and pin load steps then succeeded | `gh run view` |
| D6 stamp | none: `git-data-cutover.yml` flip precondition requires the replace job conclusion `success` AND a successful rotate-confirm step | workflow lines ~262-281 |
| Flip chain | #8209, #8609, #8573 open; #9262 and #9438 closed | `gh issue view` |

**Root cause of the blocked D6 stamp.** `.github/workflows/apply-web-platform-infra.yml` (~line 4037) loops `for VOL in hcloud_volume.git_data hcloud_volume.git_data_luks` and fails on any delete or forget action. The rotate arm (lines ~3924-3925) deliberately adds `-replace=hcloud_volume.git_data_luks`, so the assert fails on the intended action. The apply itself succeeded; only the job conclusion is red, and the flip gate reads that conclusion.

**Institutional learnings applied** (`knowledge-base/project/learnings/`): `2026-07-24-formalizing-a-provisional-provider-attestation-…` (a green lint proves nothing about citation accuracy: every word of `live_verification` must be true); `2026-09-23-arming-an-advisory-gate-turns-its-soft-defaults-into-bypasses` (hard expiry dates become freezes; enumerate branches that succeed without doing the work); `2026-10-01-the-guards-i-wrote-to-protect-the-sole-copy-…` (a guard must cover every operation that makes data unreachable); `2026-07-24-holding-a-live-overclaim-pending-infra-teardown-…` (hold legal wording and keep #6897 open until teardown); `2026-07-08-verify-disk-fullness-write-health-on-deny-all-host-without-ssh` (corroborate with provider API data, not SSH). Gap: no learning covers `non_iac_stores` removal.

**Property List.**
1. After 2026-10-22 the lint stays green only because every remaining exception is true, current and tracked by an OPEN issue.
2. A ledger row exists only for a store that exists; a store that is designed but unbuilt is not described as a plaintext exception.
3. The retained plaintext git-data volume has a dated, short, legally ruled horizon, and the date is not extended quietly (ADR-239).
4. The flip chain is not blocked by a workflow defect that no credential or authorization can clear.
5. #6897 records what happened to every row that shared its expiry.

**Cut List.** (mechanism → property → what already covers it)
- A new lint rule that checks tracking issues are OPEN → property 1 → covered by an acceptance-criteria `gh issue view` check at work time; a lint change needs network and is out of scope.
- A new Redis-without-ledger-row lint guard → property 2 (forward) → covered by plan Phase 2.11 gate plus an ADR-068 Phase 4a note plus a #5274 comment; a follow-up issue records the guard idea (CTO ruling A: build only if cheap; it is not, it edits the Python lint).
- New posture probe for the plaintext volume → property 3 → the point-in-time Hetzner read is stated as such in `live_verification`; a standing probe is a separate feature.
- Re-pointing `hcloud_volume.rehearsal_inngest` (tracks CLOSED #8285, expires 2026-12-31) → not in this ask → noted as a finding, follow-up issue.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "Close the three encryption-posture exceptions in scripts/encryption-posture-ledger.json that expire 2026-10-22, starting with redis.session_store" | Phase A1 (redis), A2 (baked credentials), A3 (git_data) | mapped |
| 2 | "measure at-rest posture read-only" | Research Insights measurements; AC1 | mapped |
| 3 | "renew with its current justification and re-point tracking_issue to an open issue" | Phase A2 | mapped |
| 4 | "If the wipe cannot happen before 2026-10-22, prepare a justified renewal." | Phase A3 | mapped |
| 5 | "Comment progress on #6897, including what happens to the zot and Inngest in-transit exceptions that share its expiry." | Phase A4, A5 | mapped |
| 6 | "Do NOT wipe anything" | Non-goals; AC8 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| Delete `redis.session_store` row + `non_iac_stores` entry | "replace the exception with a measured row" / "If ephemeral/in-memory only, record as measured and convert the row" | asked (measurement showed no store; CTO ruling A) |
| Fix the rotate-arm assert in a second PR | "find how far the git-data host rotate and flag flip have got" | asked (finding blocks the flip chain; CTO ruling C-ii) |
| In-transit rows renewed and re-pointed | "what happens to the zot and Inngest in-transit exceptions that share its expiry" | asked |
| ADR-068 Phase 4a note, #5274 comment | "replace the exception with a measured row" | inferred: a deleted row must leave a forward obligation or the next Redis ships unledgered (CTO ruling A) |
| Follow-up issue for rehearsal_inngest tracker | "Do not renew an exception just to turn the lint green; a renewal needs ... an open tracking issue" | inferred: same defect class found while verifying; filed, not fixed here |

### Split Assessment

- Subsystems touched: 3 (scripts/ledger, knowledge-base architecture docs, .github workflow + tests) 
- Planned files: ~9 | Estimated changed lines: ~250
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split into two PRs by risk, as ruled by the CTO: PR1 = ledger + docs (hard 2026-10-22 deadline); PR2 = workflow assert fix (infra apply path, own review, does not gate the deadline).

## Open Code-Review Overlap

#10112 ("review: finish the #9786 residuals once #10081 lands", mentions the ledger, including an unused rehearsal volume). Disposition: **Acknowledge** — different concern (rehearsal-volume residuals gated on #10081); PR1 touches different rows. The scope-out stays open.

## Technical Considerations

- No new infrastructure, no SSH, no Terraform change. PR2 edits only a CI workflow step and its tests.
- The lint requires `live_verification` to match `^(available|unavailable:.+)$`. A point-in-time API read is not a standing probe, so rows keep the `unavailable:` prefix and append the dated measurement (CTO ruling C-iii).
- `redis.session_store` is a `non_iac_stores` catalog entry; row and catalog entry must be removed together or the lint reports an unledgered/dangling store. No test pins the count "22 stores" (`git grep` found none outside the ledger itself).
- Horizon conflict resolved by taking the shorter date, which satisfies both rulings (see Decisions below): `hcloud_volume.git_data` and the three in-transit rows → **2026-11-12** (CLO: 30 days, this volume holds user-derived residue); `git_data.baked_credentials_on_host` → **2026-12-31** (CTO; credentials, no user data; the CLO horizon applies to the user-data volume). The template guidance is 90 days or less (not lint-enforced); 2026-11-12 and 2026-12-31 are 31 and 80 days out.

## Implementation Phases

### Phase A — PR1: ledger, architecture docs, issue comments (deadline: merge before 2026-10-22)

**A1. `redis.session_store` → removed** (CTO ruling A)
1. Delete the `stores[]` row `redis.session_store` and the `non_iac_stores` entry `"redis.session_store"` in `scripts/encryption-posture-ledger.json`.
2. `knowledge-base/engineering/architecture/diagrams/model.c4` (`sessionStore`, ~line 340): replace the AT REST sentence with "DESIGNED (ADR-068 Phase 4a), not provisioned: no host or volume exists. The Phase 4a PR must add an encryption-posture ledger row at birth." (undated on purpose; the dated measurement lives in the audit-doc correction) Keep the element and its edges (`api -> sessionStore`, `claude -> sessionStore`) and the `views.c4` include; it is still a planned container. Technology string stays.
3. `knowledge-base/engineering/architecture/encryption-posture-audit-2026-07-23.md`: add a `### redis.session_store — designed, not provisioned (2026-10-12)` entry under `## Post-audit corrections`; leave the dated snapshot row untouched.
4. `knowledge-base/engineering/architecture/decisions/ADR-068-…md`: add a Phase 4a note near the "Phase 4a" decision line (~519): "the session-Redis PR must add a ledger row at birth".
5. Comment on #5274 with the same obligation (CTO ruling A: no new issue).
6. No guard issue is filed: the optional Redis-without-ledger-row lint guard is cut (plan-review: a self-answered deferral); the ADR-068 note, the #5274 comment and plan Phase 2.11 carry the obligation.

**A2. `git_data.baked_credentials_on_host` → renewed, re-pointed** (CTO ruling B)
- `tracking_issue`: `#8620` (open, lists git-data `/etc/default/git-data-doppler`, the ingest token and the Sentry DSN in `git-data-emit`).
- `expires_on`: `2026-12-31`.
- `reevaluate_when`: "the next git-data host rebuild window, or #8620 closes, whichever is first. The 2026-10-11 rebirth (rotate run 38140050880) passed without closing the residual leg: the baked doppler_token can still derive GIT_DATA_LUKS_KEY."
- `live_verification`: `unavailable:` + "the git-data host was reborn 2026-10-11 (Hetzner API, server 169724272, created 2026-10-11T12:50:15Z); no on-host posture probe exists; related #6167". Do not claim the residual leg is closed or mitigated. The justification text is otherwise unchanged (still current; ADR-198 capability test).
- Also update the stale "born 2026-09-14 … re-birthed by run 34861860722" phrase to include the 2026-10-11 rebirth.

**A3. `hcloud_volume.git_data` → renewed with a new justification** (CTO ruling C, CLO ruling a)
- `tracking_issue`: `#6897` (stays open).
- `expires_on`: `2026-11-12`.
- `justification` (measured facts only; unmeasured items live in the ADR amendment, not the ledger): the plaintext rollback copy remains attached because the DL-2 wipe cannot run: the wipe body was deleted in #8189 and does not exist on main; it needs its own hash-bound PR and rung-2 rehearsal; it sits behind the flip chain (#8209, #8609, #8573) and the flag is disabled. The volume is never writable (ADR-239 D2), so there is no new collection and no growth. Do not claim emptiness, reopen, passphrase-loss recovery, re-escrow or #7992.
- `reevaluate_when`: "flip chain unblocked and the DL-2 wipe PR ruled executable, or 2026-11-12, whichever is first; a further slip re-opens ADR-239 and goes back to the CLO, not a silent roll".
- `live_verification`: `unavailable:` + "Hetzner API read 2026-10-12: volume 106867358 attached to server 169724272 alongside LUKS volume 107102614; point-in-time API read only, no on-host probe; contents and mount state unverified".
- `knowledge-base/engineering/architecture/decisions/ADR-239-…md`: new `## Amendment 2026-10-12 — plaintext-volume retention end re-opened` stating plainly that this is an Art. 5(1)(e) storage-limitation overrun against the 2026-10-22 target, and carrying one list: wipe (volume attached; body absent from main), served-store purge (not run; count unmeasured), flip (flag disabled; #8209, #8609, #8573 open; rotate-arm assert defect, PR2), gc cursor (unmeasured), id-bearing `.<workspace_id>.init.lock` residue since 2026-09-14 (unmeasured), Hetzner snapshot retention (unmeasured, nothing claimed about copies), owner (operator, via #8211/#6897), blocker chain, new date, and the rule that a second slip re-opens the ADR and returns to the CLO.
- No legal-doc edit (CLO ruling c: the hold stays; privacy-policy ~388/~652 and DPD ~392 and 2.3(h) unchanged). A provisional note that DPD §10.3(b) likely needs qualification goes in `decision-challenges.md` and the 2026-10-24 CLO re-ruling, not in this PR.

**A4. In-transit rows (zot x2, Inngest) → renewed on a dedicated tracker** (CTO ruling D, CLO ruling e)
- File one issue "encryption-posture: private-network in-transit exceptions (zot x2, Inngest)" carrying the re-evaluation triggers, then point all three rows' `tracking_issue` at it.
- `expires_on`: `2026-11-12` for all three (shorter of CTO 2026-12-31 and CLO 2026-11-12; the Inngest hop carries user prompts and agent output, so it is the priority to close).
- `reevaluate_when`: topology change, public or cross-network exposure, any new tenant on 10.0.1.0/24, or the link gaining TLS.
- Each row gains a per-link compensating-control statement (private-network scope, nftables restricting the peers, who can reach it), citing the Inngest (2026-10-08) and registry (2026-10-11) rebirths as dated observations only. Do not assert nftables rules were verified unless read during work.
- Work-time single command (CLO e): `grep -n -i -E 'all traffic|end-to-end|encrypted in transit' docs/legal/data-protection-disclosure.md docs/legal/privacy-policy.md`; confirm none extends to internal hops; findings go to `decision-challenges.md` and the 2026-10-24 CLO re-ruling, not a doc edit.

**A5. #6897 progress comment (and keep it open)**
Post one comment covering: redis row removed with the measurement; baked-credentials re-pointed to #8620; git_data renewed to 2026-11-12 with the blocker chain and the rotate-assert finding; in-transit rows moved to the new tracker; #6897 stays open and is bound to the teardown of `hcloud_volume.git_data` (legal-wording hold, comment 1). Include the follow-up issue numbers. Make no web-2 claim.

**A6. Verify**
`python3 scripts/lint-encryption-posture.py --repo-sweep` from the worktree (not the bare root): PASS, 0 failing; expiry warnings begin 2026-10-29 (the earliest new date is 2026-11-12 and the lint warns 14 days out). `bash scripts/lint-encryption-posture.test.sh`, `bash plugins/soleur/test/c4-count-parity.test.sh`, and the C4 tests under `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`.

### Phase B — Follow-ups during PR1 work
1. Comment on #10112 (open code-review scope-out that already covers the ledger's rehearsal rows): `hcloud_volume.rehearsal_inngest` tracks CLOSED #8285 (expires 2026-12-31); re-point or remove it there. No new issue.
2. Link PR2 (or, if PR2 is delayed, a tracking issue carrying the root cause) from #8211.
3. Put a dated reminder for 2026-11-12 in the #6897 comment (the lint warning starts 2026-10-29; the CLO re-ruling is the real event).

### Phase C — PR2: fix the rotate-arm both-volumes-preserved assert (CTO ruling C-ii; own review)
- `.github/workflows/apply-web-platform-infra.yml` (~4037, the post-apply step): add `APPLY_TARGET: ${{ inputs.apply_target }}` to that step's `env:` (the step has only `DOPPLER_TOKEN` today; `GATE_MODE` is a shell variable of the earlier plan step and does not reach it). In rotate mode, skip `hcloud_volume.git_data_luks` in the delete/forget loop and keep the assertion for plaintext `hcloud_volume.git_data`; in plain replace mode keep both volumes asserted preserved. The replace SHAPE of the LUKS volume (`["delete","create"]`) is already enforced before apply by `git_data_host_replace_gate ... rotate` (`tests/scripts/lib/git-data-host-replace-gate.sh` lines ~98-105), so the post-apply loop does not need to re-prove it.
- The post-apply loop is inline in the workflow, and `GATE_MODE` is not in scope there (it is set in the earlier plan step), so PR2 must (a) extract the loop into a new function in `tests/scripts/lib/git-data-host-replace-gate.sh` (for example `git_data_post_apply_volumes_preserved <plan-json> <mode>`), sourced by the apply step like the pre-apply gate, and (b) pass the mode in via `APPLY_TARGET`. Tests go in `tests/scripts/test-git-data-host-replace-gate.sh` against that function using the matrix below; keep `plugins/soleur/test/terraform-target-parity.test.ts` green.
- **No dispatch.** Re-running the rotate to mint a D6 stamp is a separate operator authorization naming `apply_target=git-data-host-rotate` with `confirm=ROTATE-GIT-DATA`; this plan does not request it and does not claim the stamp.

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| Renew `redis.session_store` as a plaintext exception again | A false claim about a store that does not exist; renewing would only turn lint green (forbidden). |
| Keep the redis row as "unprovisioned" mechanism | Not an allowed mechanism (luks, provider-managed, app-layer-envelope, plaintext-exception); inventing one is a lint-schema change out of scope. |
| Renew `hcloud_volume.git_data` to 2026-12-31 like the rehearsal rows | CLO: those rows hold no user data; this volume holds erased-user identifiers on a seizable disk. |
| Wipe the plaintext volume now | Destructive, body does not exist on main, gated behind the flip chain, needs operator go-ahead naming the command. |
| Single PR including the workflow fix | CTO: infra apply-path change needs its own review and must not gate the deadline. |
| Edit privacy policy / DPD wording now | CLO: the hold stays; edits follow a ratified re-ruling on 2026-10-24. |

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly; the failure is internal (every pull request red from 2026-10-23, delaying fixes that users wait for) or, worse, a ledger row that tells the next engineer a store is accounted for when it is not.
- **If this leaks, the user's data is exposed via:** the retained plaintext volume `hcloud_volume.git_data` (seizure or snapshot of a disk holding id-bearing lock residue from erased-user requests); this plan neither creates nor widens that exposure, it re-dates and re-justifies it.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** the change re-dates an existing exposure and adds no new store or connection, so it sits below `single-user incident`, which is reserved for changes that create exposure; a challenger may argue the plaintext residue itself is single-user class, in which case CPO sign-off and `soleur:engineering:review:user-impact-reviewer` apply.

## Domain Review

**Domains relevant:** Engineering, Legal

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Rulings A-E recorded in `decision-challenges.md`: delete the redis row and catalog entry together; re-point baked credentials to #8620 with 2026-12-31; renew `git_data` on a short horizon and fix the rotate-arm assert in a separate PR; renew in-transit rows on a dedicated tracker; two PRs.

### Legal (CLO)

**Status:** reviewed
**Assessment:** Renew `git_data` to 2026-11-12 at the latest, re-open ADR-239 before 2026-10-23, provisional ruling now with final re-ruling 2026-10-24; hold stays on published wording; no legal-doc mentions of the session store, so the row removal is clean (check `knowledge-base/legal/article-30-register.md`); renew in-transit rows on the same horizon with per-link compensating-control statements; grep DPD/privacy policy for over-broad TLS language.

## Encryption Posture

```yaml
at_rest:
  - store: redis.session_store
    mechanism: removed (store does not exist: designed in ADR-068 Phase 4a, not provisioned)
    evidence: Hetzner inventory 2026-10-12 (5 servers, 6 volumes, none a session Redis); apps/web-platform/package.json has no Redis client; knowledge-base/engineering/architecture/diagrams/model.c4:340 (sessionStore)
    defends_against: n/a - nothing is stored
    does_not_defend: n/a as a store; when Phase 4a provisions it, its at-rest posture is undefined until that PR adds a ledger row
    disclosed_as: not-publicly-claimed
    live_verification: unavailable:no host exists to probe; measured absence from the Hetzner API 2026-10-12
  - store: git_data.baked_credentials_on_host
    mechanism: plaintext-exception
    evidence: apps/web-platform/infra/cloud-init-git-data.yml write_files /etc/default/git-data-doppler and /etc/default/git-data-betterstack (0600), sentry_dsn inside /usr/local/bin/git-data-emit (0755)
    defends_against: file-read-only primitive for the non-root git account on the two 0600 files; non-root metadata-endpoint reads (#7772 nftables drop)
    does_not_defend: code execution as root reads user_data from the metadata endpoint; the 0755 sentry_dsn copy; the baked doppler_token's derivation path to GIT_DATA_LUKS_KEY
    disclosed_as: not-publicly-claimed
    live_verification: unavailable:host reborn 2026-10-11, no on-host posture probe
  - store: hcloud_volume.git_data
    mechanism: plaintext-exception
    evidence: apps/web-platform/infra/git-data.tf:264 (format = "ext4", no LUKS apparatus)
    defends_against: nothing at the volume layer; never writable (ADR-239 D2)
    does_not_defend: a seized or snapshot disk exposes id-bearing lock residue and any pre-cutover git data still resident
    disclosed_as: not-publicly-claimed
    live_verification: unavailable:Hetzner API read 2026-10-12 shows volume 106867358 attached to server 169724272; no on-host probe
in_transit:
  - connection: web hosts -> zot registry (10.0.1.30:5000) and runner -> zot over the CF Tunnel final leg
    enforced_at: apps/web-platform/infra/zot-registry.tf; .github/actions/cf-tunnel-registry-bridge/action.yml
    tls: none on the private-network leg (CF leg TLS 1.2+)
    cert_verification: off
    does_not_defend: passive on-net attacker reads image bytes and the pull credential; integrity from digest pinning only
    disclosed_as: not-publicly-claimed
  - connection: web-platform app <-> inngest host (10.0.1.40:8288)
    enforced_at: apps/web-platform/infra/ci-deploy.sh; cloud-init.yml (INNGEST_BASE_URL); inngest-host.tf; cron-egress-nftables.sh
    tls: none
    cert_verification: off
    does_not_defend: passive on-net attacker reads INNGEST_EVENT_KEY, the hashed signing key, event payloads and step outputs (user prompts and agent output)
    disclosed_as: not-publicly-claimed
exception:
  justification: see Phase A2-A4 (per-row text; renewed only with a current, measured justification)
  tracking_issue: "#8620 (baked credentials); #6897 (git_data); new in-transit tracker (three connection rows)"
  reevaluate_when: per row, Phase A2-A4
  expires_on: "2026-12-31 (baked credentials); 2026-11-12 (git_data volume and the three in-transit rows)"
```

## Architecture Decision (ADR/C4)

### ADR
- Amend **ADR-239** with `## Amendment 2026-10-12 — plaintext-volume retention end re-opened` (re-open rule in its "Retention end" section; CLO inputs). No new ADR: this re-dates an existing decision.
- Add a Phase 4a note to **ADR-068** (the session-Redis PR must ledger at birth).

### C4 views
Read all three files `diagrams/{model.c4,views.c4,spec.c4}`. Actors and systems for this change: no new external human actor, no new vendor or system, no new container or data store, no access relationship change. Already modeled and unchanged: `platform.infra.sessionStore` (model.c4:340), its edges `api -> sessionStore` and `claude -> sessionStore` (model.c4:897-898), the `views.c4:65` include, `gitDataStore`, `inngestRedis`, `zotRegistry`. The only edit is `sessionStore.description` (the "AT REST: unconfirmed" sentence is falsified by the measurement). `spec.c4` has no `sessionStore` reference. `plugins/soleur/test/c4-count-parity.test.sh` passes on the branch today (`ALL TESTS PASSED`) and is re-run after the edit.

### Sequencing
ADR-239 amendment is authored now describing the re-dated target; the wipe it anticipates is not postponed to a separate issue but is explicitly gated and re-ruled on 2026-10-24.

## Observability

```yaml
liveness_signal:
  what: encryption-posture lint sweep (Layer A) plus the 14-day expiry warning
  cadence: per pull request
  alert_target: CI required check on every PR
  configured_in: scripts/lint-encryption-posture.py
error_reporting:
  destination: CI job log and required-check status
  fail_loud: "FAIL: ... exception.expires_on ... is in the past" and a non-zero exit
failure_modes:
  - mode: an exception expires with no renewal or removal
    detection: the sweep prints a warning from 14 days out and fails after expires_on
    alert_route: required check turns every PR red
  - mode: a renewed row points at a closed issue
    detection: not detected by the lint; acceptance criterion AC3 checks it at work time with gh issue view
    alert_route: reviewer at PR time
logs:
  where: GitHub Actions job log
  retention: GitHub default run-log retention
discoverability_test:
  command: python3 scripts/lint-encryption-posture.py --repo-sweep
  expected_output: PASS
```

## Guard Contract

### Guard 1 — rotate-arm both-volumes-preserved assert (PR2)

**Property.** After a git-data apply, no plaintext or LUKS git-data volume is lost except the LUKS volume in the one dispatch that is meant to replace it, and in that dispatch it is replaced (delete and create), never merely deleted.

**Assembly.** The chokepoint is the single post-apply step `Terraform apply (git-data-host -replace) — both-volumes-preserved assert` in `.github/workflows/apply-web-platform-infra.yml` (the `for VOL in …` loop, ~4037), which both `git-data-host-replace` and `git-data-host-rotate` flow through (one job, `if:` at ~3713). The sibling checks in the same step are the attachment loop (~4053) and the NIC check (unchanged). Other jobs with a volume-preserved loop (`registry`, `inngest_redis_luks`) are separate chokepoints and are not touched. The matrix drives the function extracted from the loop (see Phase C).

**Mutation matrix.**

| # | Edit (must drive the guard RED) | Target |
|---|---|---|
| 1 | rotate-mode plan with a delete on `hcloud_volume.git_data` (plaintext) | plaintext preservation under rotate |
| 2 | plain-replace plan with a delete on `hcloud_volume.git_data_luks` | LUKS preservation outside rotate |
| 3 | empty `resource_changes` (zero volumes iterated) must not report PASS | the guard's own dispatch (non-vacuity) |

Rows for the LUKS volume's replace shape (`["delete","create"]`, order, delete-only) already exist in the pre-apply rotate gate tests (R1-R2 and neighbours in `tests/scripts/test-git-data-host-replace-gate.sh`); PR2 does not duplicate them.

**Harness rows.** Harness RED: delete the loop body from the extracted function and confirm the suite fails (the suite must not exit 0 on `0 passed`). Must-PASS non-canonical input: a rotate plan with `git_data_luks` actions `["create","delete"]` plus unrelated resource changes, differing from the canonical `["delete","create"]` in a way the contract permits (rotate mode must not red on a replace, in either order).

**Anchor.** The guard compares a plan to expected actions, not a stored value; the anchor is the committed test fixtures reviewed in the PR plus the merge-base diff of the gate lib. A weakening that edits both the workflow step and the fixtures in one commit is caught only by review; state this limit in the PR.

## Acceptance Criteria

- [ ] AC1: Measurements recorded with date and source in the plan (Research Insights) and re-checked at work time; no row claims more than a point-in-time API read.
- [ ] AC2: `python3 scripts/lint-encryption-posture.py --repo-sweep`, run from the worktree, prints `PASS`, 0 failing; no `redis.session_store` anywhere in `scripts/encryption-posture-ledger.json` (`grep -c redis.session_store` returns 0).
- [ ] AC3: Every touched row's `tracking_issue` resolves OPEN: `gh issue view <N> --json state -q .state` returns `OPEN` for #8620, #6897 and the new in-transit tracker.
- [ ] AC4: Dates: `hcloud_volume.git_data` and the three in-transit rows `2026-11-12`; `git_data.baked_credentials_on_host` `2026-12-31`; none later than the CLO horizon for user-data rows.
- [ ] AC5: `model.c4` `sessionStore` states designed-not-provisioned; `bash plugins/soleur/test/c4-count-parity.test.sh` and the C4 syntax/render tests pass.
- [ ] AC6: ADR-239 amendment and ADR-068 Phase 4a note merged in PR1; #5274 comment posted; #10112 comment posted (rehearsal_inngest tracker); no guard issue.
- [ ] AC7: #6897 comment posted covering all six rows, #6897 left OPEN, no web-2, reopen, passphrase-loss, re-escrow, #7992 or emptiness claim anywhere.
- [ ] AC8: No `workflow_dispatch`, `terraform apply`, Doppler write, volume wipe or destroy executed; PR2 tests pass with the three-row matrix and the workflow change is merge-only.
- [ ] AC9: No legal document under `docs/legal/` is edited in PR1.

## Test Scenarios

- Given the ledger after PR1, when the lint sweep runs, then PASS and warnings only for rows expiring 2026-11-12 (from 2026-10-29).
- Given a plan JSON with `git_data_luks` replaced and `git_data` untouched in rotate mode, the gate passes; given the same with `git_data` deleted, it fails.
- Given a plain replace plan that deletes `git_data_luks`, the gate fails.

## Files to Edit

- `scripts/encryption-posture-ledger.json`
- `knowledge-base/engineering/architecture/diagrams/model.c4`
- `knowledge-base/engineering/architecture/encryption-posture-audit-2026-07-23.md`
- `knowledge-base/engineering/architecture/decisions/ADR-239-git-data-serves-from-luks-at-birth.md`
- `knowledge-base/engineering/architecture/decisions/ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md`
- `.github/workflows/apply-web-platform-infra.yml` (PR2)
- `tests/scripts/test-git-data-host-replace-gate.sh`, `tests/scripts/lib/git-data-host-replace-gate.sh` (PR2)

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-encryption-posture-exceptions-2026-10-22/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-encryption-posture-exceptions-2026-10-22/decision-challenges.md`

## Dependencies & Risks

- The CTO and CLO horizons conflict; the shorter date is used so both hold. The cost is a second renewal round on 2026-11-12 if the flip chain is still blocked (#8209, #8609, #8573), which is likely; the CLO has said the next ruling is a re-ruling, not a renewal. This is a schedule fact for the operator, not a technical question.
- The D6 stamp needs a fresh rotate dispatch after PR2; that is an irreversible-class action requiring explicit operator authorization naming the command.
- A deleted `redis.session_store` row removes the only record that a session store is unledgered; the ADR-068 note, #5274 comment and plan Phase 2.11 are the substitutes.
- Row text must not state anything not measured; the lint cannot check this (learning: a green sweep proves nothing about citation accuracy).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails deepen-plan; it is filled here.
- The bare repo root gives 7 false lint failures; always run the lint from a worktree.
- `live_verification` must start with `unavailable:` or equal `available`; do not write a prose-only value.
- Removing `redis.session_store` from `stores[]` without `non_iac_stores` (or the reverse) breaks the lint.
