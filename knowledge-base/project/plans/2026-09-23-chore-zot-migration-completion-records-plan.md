---
title: "chore(6122): close out the GHCR-to-zot migration records outside #8651 — #7077 verdict, 1d sequencing, stale ADR/tasks/issue records, ADR-169 vs 5.3b write-up"
date: 2026-09-23
slug: chore-zot-migration-completion-records
branch: feat-one-shot-zot-migration-completion
issue: 6122
type: chore
lane: cross-domain
brand_survival_threshold: none
pr: 8666
---

# chore(6122): close out the GHCR-to-zot migration records outside #8651

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed). No `spec.md` exists for this branch.

## Enhancement Summary

**Deepened on:** 2026-09-24. **Sections enhanced:** 6 (Research Insights, Phase 1.2, Phase 2, section 4, Acceptance Criteria, Sharp Edges).
**Agents used:**

- **Plan phase:** learnings-researcher, functional-discovery, soleur:engineering:cto, the scoped advisor consult, spec-flow-analyzer.
- **Plan review:** dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer.
- **Deepen:** git-history-analyzer, a verify-the-negative pass.

**Halt gates:**

| Gate | Result |
|---|---|
| 4.6 User-Brand Impact | present; threshold `none`; Files to Edit are all under `knowledge-base/`, not a sensitive path |
| 4.7 Observability | skipped: pure-docs plan |
| 4.8 PAT | no match |
| 4.9 UI | skipped: no UI surface |
| 4.10 Encryption | skipped: no `.tf`, cloud-init or migration file edited, and no store is introduced |
| 4.11 Guard | skipped: no guard deliverable |
| 4.55 Downtime | skipped: no downtime operation |

### Key Improvements

1. **#7077.** All three acceptance items verified on `main`. The positive bridge probe (item 2) is cut, because building it would re-break the #7278 inventory caller.
2. **#8036 1d.** Sequenced after #8660 on three independent grounds:
   - the #8660 test collision
   - `host_scripts_content_hash` and the coherence preflight
   - `hcloud_server.inngest` has no `ignore_changes=[user_data]`, so 1d needs a planned inngest replace
3. **Section 4.** The ADR-169 vs 5.3b write-up now covers four options in neutral order. It adds three facts that bind every option:
   - "stop GHCR push" is not a toggle: buildx pushes to GHCR, and `crane copy` fills zot from there
   - the host GHCR egress still carries the anonymous cosign and zot-image pulls
   - #8660 sequencing
4. **Records corrected before posting:**
   - 1.8 is marked `[~]`, not `[x]`: two of its checks never ran (DC1). **Superseded 2026-09-24:** ticked `[x]` on live measurement; see DC1.
   - #6427's scope names the real soak keys (`appboot`, `appserved`, `freshboot`, `gate`) and the emit sites that survive 5.3b
   - #6073 loses `action-required` too, so the SLA cron cannot re-add p0
5. **#7077 and #6073 are closed directly** (DC3). The PR carries no closing keyword, and AC4 asserts the empty set, URL forms included.

### New Considerations Discovered

- 5.3b's "remove GHCR egress allow" would break cosign verification (`COSIGN_IMAGE=ghcr.io/sigstore/…`) and the registry host's own boot (`zot_image_*` = `ghcr.io/project-zot/…`). Posted as a fact in section 4, not decided.
- B3's CI-side GHCR read uses `secrets.GITHUB_TOKEN`, not a PAT (`apply-web-platform-infra.yml`), so 5.4/5.5 (PAT and minter retirement) do not depend on the push.

## Overview

This plan covers the ADR-096 (GHCR-to-zot) work that is left after #8651. #8651 is being
fixed in a parallel worktree (draft PR #8660) and is not in scope here.
**`apps/web-platform/infra/cloud-init.yml` is not edited.**

What was measured on `main` @ `fa1e2c8733` (2026-09-23) changes the shape of the work. No
engineering fix remains in scope. Every remaining in-scope item is a record that disagrees with
the code or with what production has done:

| # | Item | Verdict | Deliverable |
|---|---|---|---|
| 1 | #7077 inngest mirror fail-closed invariant | **Already satisfied.** All three acceptance items hold on `main`. Item 2 holds by its property, not by the mechanism the issue proposed. | Evidence comment, then `gh issue close 7077 --reason completed` in the work phase |
| 2 | #8036 item 1d (retire boot-time `docker login ghcr.io`) | **Sequenced after #8660. Not implemented here.** Every 1d site is in a file #8660 edits or a test #8660 edits, and one is inside the host-script content hash. | Sequencing comment on #8036. Supersession-condition comment on #6410 (it stays open) |
| 3a | ADR-096 top `## Status` block | Stale. It still says the flip is inert until provisioning (1.8) and backfill (1.9) | Rewrite the block (lines 9-17 only) |
| 3b | `feat-registry-oidc-migration/tasks.md` | 1.9 and 2.4 are done but unticked. 1.8 is half done (superseded 2026-09-24: done, see DC1): the host serves, but its two named checks have no recorded run. 5.3 is not split | Tick 1.9 and 2.4 with evidence. Mark 1.8 `[~]` (partial) with a note naming the two unrun checks. Split 5.3 into 5.3a (done) and 5.3b |
| 3c | #6073, #6122, #6630, #6427 | Stale labels, stale close criteria, stale scope | `gh` edits and comments, listed below |
| 4 | ADR-169 against 5.3b deadlock | Needs an operator decision | Options A and B written up below and posted to #6122. **No option is chosen** |

> **Superseded 2026-09-24 (review P1):** the bottom line below is wrong. The soak cannot pass until #8651 closes (its
> `WEB_BLOCKER` arm; it also needs `app_zot` evidence), and its FAIL verdict needs a re-armed window. The corrected
> chain is in the revised #6122 comment. The paragraph is kept as the record of what the brief asked for.

**The bottom line, stated plainly: the gap between today and "migration complete" is not engineering.
It is one authorization act on #6122. That act has been reserved to the operator twice and has not
been taken.**

- **First reservation, 2026-07-15 (#6122).** "Do not close [#6500] as a way to unblock the gate —
  closing it *is* the authorization act."
- **Second reservation, 2026-09-23 (#6122).** Enrolling the soak in the sweeper, or closing it on
  `RESULT: PASS`, is "a deliberate reservation … not mine to do".

The soak's backfilled verdict is a recorded FAIL. Every task that is not yet done waits behind that
act: 5.3b, 5.4, 5.5, 5.6 and #6129. The ADR-169 restore-source choice in section 4 is part of the
same decision on the same thread. How much engineering follows the act depends on that choice:

| Option | Build cost after the act |
|---|---|
| A | Several PRs, plus about €19.49/month if the replica uses the same type |
| B1 | One slice: a bucket, a CI step, and the restore engine re-sourced |
| B2 | No new infrastructure, but ADR-169's independence criterion has to be weakened |
| B3 | No new build; GHCR push stays |

The act comes first and gates all four. #8651 and PR #8660 are the one piece of in-flight
engineering, and they are out of scope here. The per-option qualifier is recorded as DC2 in
`specs/feat-one-shot-zot-migration-completion/decision-challenges.md`.

## Research Reconciliation — Brief vs. Codebase

| Brief claim | Reality on `main` (2026-09-23) | Plan response |
|---|---|---|
| #7077: "a soft-failed zot bridge SKIPS the mirror, leaving mirror_status unset" | Fixed by #7252 (merged 2026-08-04, `636a68aee7`). That diff deleted the live `if: steps.zot_bridge.outcome == 'success'` line (confirmed: `git show 636a68aee7` shows it as a removed line). The remaining hits in the workflow are comments that warn against re-adding it | Close with evidence |
| #7077 item 2: replace the `nc -z` listener check with a positive `/v2/` probe | `nc -z 127.0.0.1 5000` is still in `.github/actions/cf-tunnel-registry-bridge/action.yml`. The property it was meant to buy ("a dead bridge path is reported as a bridge failure") already holds another way, on all 5 callers. See the Cut List | Close item 2 as covered by that property. Do not build the probe |
| #7077 item 3: "cloud-init-inngest.yml hard-pins a ghcr.io ref with no zot path" | False since #7516 (merged 2026-08-13). `cloud-init-inngest.yml` resolves a zot-primary `ZIREF` and falls back to GHCR. On 2026-09-23 at 19:37:18Z a boot logged `inngest_zot` | Record it as decided and built |
| #8036 item "1d" | #8036's own thread does not name "1d". It is defined in the 1c plan (`2026-09-23-fix-retire-host-ghcr-read-path-plan.md`, Non-Goals row): "Retire cloud-init's boot-time `ghcr_login`", deferred as a tracked follow-up. `cloud-init.yml` already cites it inline (`… fresh-boot ghcr_login (1d)`) | Use that definition |
| tasks.md 1.8 "GATE … EXACTLY 2 non-`DOPPLER_*` secrets, both `ZOT_*`" | The boot isolation self-check in `cloud-init-registry.yml` (the "Isolation self-check — the load-bearing, fail-CLOSED defense" block) now admits **4** named secrets: `ZOT_PULL_TOKEN`, `ZOT_PUSH_TOKEN`, `BETTERSTACK_LOGS_TOKEN` and `REGISTRY_LUKS_KEY`. No run of the pre-flip scoped-token assertion (isolation-fix plan AC11) is on record. `betteruptime_heartbeat.registry_prd` is still declared `paused = true` | Mark 1.8 `[~]` on serving evidence. The note names AC11 (updated to 4 admitted secrets) and the paused heartbeat as not done |
| #6630 close criterion names `PRELUDE: docker login ghcr.io ok` | 1c (#8600) deleted that log line. `scripts/followthroughs/zot-login-gate-erofs-repaired-6565.sh` is now "ONE-LEGGED SINCE #8036 1c": only `ZOT_GATE: active … docker login … ok` counts | Edit the body so it names the zot-gate line |
| #6427 "correct ADR-096:103-106 + issue-alerts.tf" | Its original scope was absorbed by #6285 / PR #6424 (merged 2026-07-15). The remaining scope, "re-point or retire the soak in the same slice as 5.3", is half done. 5.3a narrowed `FAIL_QUERIES` and the alarm. 5.3b is not done | Narrow the body to the 5.3b slice |
| 5.3b includes "remove GHCR egress allow" | Anonymous public pulls still go to `ghcr.io`: the cosign verifier (`ci-deploy.sh` `readonly COSIGN_IMAGE="ghcr.io/sigstore/cosign/cosign@sha256:…"`) and zot's own image (`zot-registry.tf` `zot_image_amd64` / `zot_image_arm64` = `ghcr.io/project-zot/…`) | Record this as a scoping hazard for 5.3b in the #6122 write-up. Do not decide it here |

## Research Insights

### Premise Validation (Phase 0.6)

Every cited issue was checked with `gh issue view --json state,title,labels,milestone` on 2026-09-23:

- **Open:** #7077, #8036, #6410, #6073, #6122, #6630, #6427, #6126, #6500, #6129, #8651, #6565.
- **Closed:** #8037, closed by the sweeper on 2026-09-22 at 12:58Z with PASS on `IMAGE_VERIFY: ok` against a zot ref.
- **Draft:** PR #8660.

The following were confirmed on `origin/main` with `gh pr view` and `git show`:

| PR | Merged | Commit |
|---|---|---|
| #7252 | 2026-08-04 | `636a68aee7` |
| #7516 | 2026-08-13 | `5c85b1c3e9` |
| #8600 (1c / 5.3a) | 2026-09-23 18:31:57Z | `25aa2712ed` |
| #8636 (1c probe fixes) | 2026-09-23 21:24:27Z | `e5b84bf0c9` |
| #8653 (soak web-host blocker arm) | 2026-09-23 20:34:07Z | `3aaaede525` |
| #8543 (cosign verify fix) | 2026-09-22 11:59:06Z | `ec68b3ec42` |
| #6424 | 2026-07-15 | `ee997b6e3b` |

`gh pr view 8660 --json files` confirms the brief's collision list. It also adds
`scripts/fresh-host-boot-trail.sh`, ADR-114, ADR-123, `model.c4`, the encryption ledger and a
`web-fresh-boot-zot-8651` follow-through. The #8660 patch's only ADR-096 hunk is
`@@ -1273,3 +1273,83 @@`, an append at the end of the file. It does not touch the Status block at
lines 9-17. It does not touch `feat-registry-oidc-migration/tasks.md`.

**Stale premise found:** #7077 is fully resolved. The plan's deliverable for it changes from *fix*
to *close with evidence*.

### Property List (Phase 0.6b)

- **P1.** A reader of #7077 sees that its invariant holds on `main`, with pointers they can check.
- **P2.** A reader of #8036 and #6410 sees when 1d can land and what closes #6410. Nobody can mistake 1d for done or abandoned.
- **P3.** ADR-096's Status block tells the truth about the cutover and the retirement state.
- **P4.** The registry-oidc `tasks.md` matches what production has done.
- **P5.** Issue labels, milestones and close criteria (#6073, #6122, #6630, #6427) match reality. A close criterion never names a signal that cannot be emitted.
- **P6.** The operator has an unbiased A/B write-up of the ADR-169 against 5.3b deadlock on #6122.

### Cut List (Phase 0.6b)

- **Positive `/v2/` probe in `cf-tunnel-registry-bridge` (#7077 item 2).**
  - **Property:** a dead bridge path is reported as a bridge failure, not blamed on a later step.
  - **Already covered on the authority file** (`.github/actions/cf-tunnel-registry-bridge/action.yml`):
    - Four callers leave `skip-docker-login` unset: `reusable-release.yml`, `build-inngest-bootstrap-image.yml`, `build-inngest-config-bundle.yml` and `apply-web-platform-infra.yml`. For them, the composite's own `Docker login to zot (127.0.0.1:5000, zot-push htpasswd)` step dials the origin, so a dead path fails the composite.
    - The fifth caller, `registry-zot-inventory.yml`, sets `skip-docker-login: 'true'`. It opens with `scripts/zot-inventory.sh`'s own origin check (anchor: `B2 — origin reachability FIRST`).
  - **Building it would do harm.** A probe that aborts inside the composite brings back the fail-closed abort that #7278 avoided on purpose for the inventory caller. The workflow comment says why: "the most likely outcome of NOT skipping is that the composite aborts and the inventory never runs".
- **A 1d slice in this PR.**
  - **Property:** the boot path stops presenting the revoked GHCR credential.
  - **Why it is cut:** every site is in #8660's file set or pinned by #8660's tests. `soleur-host-bootstrap.sh` is also in `local.host_script_files`, so editing it moves `host_scripts_content_hash` and trips `apps/web-platform/infra/scripts/host-image-coherence-preflight.sh`.
  - **What covers it:** #8036 and the 1d follow-up issue, sequenced after #8660.

### Value-proposition measurement (Phase 0.6c)

Not applicable. No mechanism is justified by a cost or performance saving.

### Relevant files (authority, cited by content anchor)

- `.github/workflows/build-inngest-bootstrap-image.yml`:
  - step `id: zot_bridge` (`continue-on-error: true`, with the comment "#7203 shipped … the #6416 defect verbatim")
  - step `id: zot_mirror` (the comment "NO `if:` — deliberately", `env: BRIDGE_OUTCOME: ${{ steps.zot_bridge.outcome }}`, and the branch `if [ "${BRIDGE_OUTCOME:-}" != "success" ]; then degraded bridge_down …`)
  - the Slack degrade step (`if: ${{ !cancelled() && steps.zot_mirror.outputs.mirror_status == 'degraded' }}`)
  - the job output `mirror_status: ${{ steps.zot_mirror.outputs.mirror_status }}`
- `apps/web-platform/infra/inngest-bootstrap-mirror-only.test.sh`, run by `infra-validation.yml`. Its checks include:
  - "zot_mirror is NOT gated on the bridge outcome (a skipped step cannot emit)"
  - "the bridge result reaches the script as OUTCOME, not conclusion"
  - "zot_bridge keeps continue-on-error: true unconditionally"
  - the literal `BRIDGE_COND = 'if [ "${BRIDGE_OUTCOME:-}" != "success" ]; then'`
- `.github/actions/cf-tunnel-registry-bridge/action.yml`: the listener loop `nc -z 127.0.0.1 5000`, the `Docker login to zot` step gated `if: inputs.skip-docker-login != 'true'`, and the FR-B2 log dump.
- `apps/web-platform/infra/cloud-init-inngest.yml`: the `#7462 (ADR-096): resolve the effective ref ONCE, zot-primary` block (`ZIREF=…`, `timeout 180 docker pull "$ZIREF"`) and the boot-time `docker login ghcr.io` (a 1d site).
- `apps/web-platform/infra/soleur-host-bootstrap.sh`: `STAGE=ghcr_login` / `ghcr_login_warn` (a 1d site; in `server.tf` `local.host_script_files`).
- `knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md`:
  - `## Status` (lines 9-17), which is stale
  - the task-5.3 amendment "Amendment 2026-09-23 (#8036 item 1c): 5.3 SPLITS INTO 5.3a AND 5.3b, AND 5.3a IS DONE"
  - the amendment "Amendment 2026-09-22 (#6122) — the cutover happened on 2026-07-17 …"
  - clause (g)
- `knowledge-base/engineering/architecture/decisions/ADR-169-what-authorizes-destroying-the-sole-pull-path.md`: `## Decision`, `### The independence criterion`, `## Alternatives considered` (the "Require a second mirror to exist" row), predicates A1/A2, `## Consequences`, and the 2026-08-16 P5 amendment.
- `knowledge-base/engineering/operations/runbooks/zot-registry-revert.md` § "Cutover record (#6122)".
- `scripts/followthroughs/zot-login-gate-erofs-repaired-6565.sh` (the "ONE-LEGGED SINCE #8036 1c" classifier), `scripts/followthroughs/ghcr-read-retired-8036.sh` and `scripts/followthroughs/zot-soak-6122.sh` (`declare -A FAIL_QUERIES`).

### Institutional learnings applied

- `2026-07-06-ghcr-app-token-cannot-pull-and-oidc-needs-native-identity-source.md`. This is the #6073 answer: GHCR refuses App installation tokens for `docker pull`. ADR-096's `Supersedes: ADR-088` line records it.
- `2026-06-29-brainstorm-soak-gated-tracker-item-and-grep-helper-sig-before-accepting-obstacle.md`. Soak-gated items are recorded as gated. They are never ticked early.
- `2026-02-22-github-issue-auto-close-syntax.md` and AGENTS `wg-use-closes-n-in-pr-body-not-title-to`. A closing keyword with `#N` anywhere in the PR title, body or a commit message closes that issue. This PR uses none. #7077 and #6073 are closed directly with `gh issue close`.
- AGENTS `hr-before-asserting-github-issue-status`. Every status claim above was re-read live on 2026-09-23. The work phase re-reads state before each `gh` write.
- AGENTS `hr-menu-option-ack-not-prod-write-auth` and `hr-technical-fork-is-not-an-operator-question`. Section 4 is a **reserved authorization** that the operator has already declared twice. It is not a technical fork. So it is written up, and not decided.

### CLAUDE.md / constitution conventions

- Cite by content anchor, not line number (`cq-cite-content-anchor-not-line-number`). The one exception is the Status block's "lines 9-17", which this plan edits.
- Amend ADRs in place. Do not claim a new ordinal.

### Deepen-pass verification (2026-09-24)

**Attribution** (git-history-analyzer, against `origin/main`). All confirmed:

- #7252 removed the live bridge gate.
- #7516 added the zot-primary `ZIREF` path.
- #6424 corrected the "load-bearing at Phase-5" text in ADR-096 and `issue-alerts.tf`.
- #8600 deleted the prelude GHCR login and made the 6565 probe one-legged.
- #8543 fixed cosign verify for #8037.
- Run `31681702541` and "392 pulls" appear in ADR-096 and the revert runbook.
- All 8 cited SHAs are ancestors of `origin/main` (`git merge-base --is-ancestor`).

**Negative claims** (verify-the-negative pass). All 9 confirmed:

- No test or lint reads ADR-096's Status block or the registry-oidc `tasks.md`. `[~]` already appears there (item 1.5).
- Only `registry-zot-inventory.yml` skips the bridge login, and `zot-inventory.sh` "B2 — origin reachability FIRST" probes `/v2/`.
- `soleur-host-bootstrap.sh` is in `local.host_script_files`.
- `inngest-host.tf` says "Deliberately NO lifecycle.ignore_changes=[user_data]".
- No workflow or issue carries a `zot-soak-6122.sh` follow-through directive.
- `FAIL_QUERIES` is exactly `gate`/`freshboot`/`appboot`/`appserved` (floor asserts 4).
- `cloud-init.yml` emits `app_ghcr_fallback` and `app_ghcr_served`.
- `cloud-init-inngest.yml` emits `inngest_ghcr_fallback`. So does the dead colocated block in `cloud-init.yml` (`web_colocate_inngest` defaults to `false`).
- The ADR-169 restore reads GHCR with `secrets.GITHUB_TOKEN`.

**Rule IDs.** Every `hr-`/`wg-`/`cq-` id cited here resolves to an active `[id: …]` in `AGENTS.md`.

## Implementation Phases

All GitHub writes below happen in the **work phase**, not in planning. Each one is preceded by a
re-read (`gh issue view <N> --json state,labels,milestone`). If the state has moved since
2026-09-23, stop and reconcile before writing.

### Phase 1 — Repo record edits (the only file diffs in this PR)

**1.1 ADR-096 `## Status` block.** Replace lines 9-17 (from `## Status` up to, not including,
`## Amendment 2026-07-30`) with:

```markdown
## Status

**Adopting — cut over, not yet accepted.** zot has served production pulls since
**2026-07-17T19:51:49Z** and has been the **sole** pull path since about 2026-07-29, when the GHCR
read PAT was revoked outside any repo change (amendments 2026-07-30 and 2026-09-22; cutover record
in `runbooks/zot-registry-revert.md` § "Cutover record (#6122)"). A zot-served *fresh* web boot has
not yet been observed (`stage:"app_zot"` has 0 events; #8651). Retirement is partial.
**5.3a** (the `ci-deploy.sh` GHCR read path) was delivered on 2026-09-23 by #8036 item 1c; see the
task-5.3 amendment. **5.3b, 5.4, 5.5 and 5.6 are pending** behind the #6122 soak authorization.
The backfilled `zot-soak-6122.sh` verdict is a recorded FAIL, and #6500 is open. 5.3b's
"stop GHCR push" also collides with ADR-169, whose restore gate reads GHCR (see #6122). This ADR
flips to **accepted** at 5.6.
```

The header bullet `- **Status:** Adopting` (line 3) stays as it is. The ADR is still adopting.

**1.2 `knowledge-base/project/specs/feat-registry-oidc-migration/tasks.md`.** Make these edits
in place. Do not rewrite any other line.

- **Superseded 2026-09-24 (DC1): 1.8 is ticked `[x]`.** The live heartbeat reads `up`, and the config holds exactly the 4 admitted secrets. The original instruction follows. `- [ ] 1.8` → `- [~] 1.8 …` (`[~]` is this file's existing partial marker; see 1.5). Append this note (DC1 in `specs/feat-one-shot-zot-migration-completion/decision-challenges.md`):
  > **Partial — evidence:** deployed and serving. The first zot-served web pull was 2026-07-17T19:51:49Z, with 392 zot-served pulls in the 90 days to 2026-09-22 (`runbooks/zot-registry-revert.md` § "Cutover record (#6122)"). Every serving boot passed the fail-closed boot self-check in `cloud-init-registry.yml` ("Isolation self-check — the load-bearing, fail-CLOSED defense"). **Not done:**
  > - The pre-flip scoped-token isolation assertion (isolation-fix plan AC11) has no recorded run. The admitted set is now **4** (`ZOT_PULL_TOKEN`, `ZOT_PUSH_TOKEN`, `BETTERSTACK_LOGS_TOKEN`, `REGISTRY_LUKS_KEY`), not "EXACTLY 2".
  > - "Heartbeat green" is not met: `betteruptime_heartbeat.registry_prd` is still `paused = true` in `apps/web-platform/infra/zot-registry.tf`.
- `- [ ] 1.9` → `- [x] 1.9 …` and append:
  > **Done — evidence:** zot serves both images. Web: the 392 zot-served pulls above. Inngest: mirror_only run 31681702541 reported GHCR and zot digests identical to the pin (ADR-096 amendment 2026-08-13 (#7462/#7516)), and a 2026-09-23 19:37:18Z boot logged `inngest_zot` (#6122 comment 2026-09-23). The pinned inngest version has since moved past `v1.1.18`.
- `- [ ] 2.4` → `- [x] 2.4 …` and append:
  > **Done — evidence:** `IMAGE_VERIFY: ok ref=10.0.1.30:5000/jikig-ai/soleur-web-platform@sha256:24ef3c95…` on the first deploy after #8543's apply (2026-09-22 12:27:41Z, host `3f07b655`). #8037 was auto-closed by `cosign-verify-live-8037.sh` PASS on 2026-09-22 at 12:58Z. That shows a tag build that is pullable and signature-verified from zot.
- Replace the single `- [ ] 5.3 (post-soak) remove fallback branch; stop GHCR push; remove GHCR egress allow` line with two lines:
  - `- [x] 5.3a Remove the ci-deploy.sh (rolling-deploy) GHCR read path — **done 2026-09-23 by #8036 item 1c (PR #8600, merge 25aa2712ed; probe fixes PR #8636, e5b84bf0c9)**, on the no-reachable-success-arm ground recorded in ADR-096's task-5.3 amendment. Not a soak pass.`
  - `- [ ] 5.3b (post-soak) remove the two cloud-init.yml fresh-boot GHCR branches; stop GHCR push; remove GHCR egress allow — **not done**. Blocked by the #6122 soak authorization and by ADR-169 (the restore gate reads GHCR; see the #6122 A/B write-up). Also sequenced after #8660 (#8651). The egress item needs re-scoping first, because the cosign verifier and zot images still pull anonymously from ghcr.io.`
- 5.4, 5.5 and 5.6 stay unticked and unchanged.

### Phase 2 — GitHub record edits (work phase runs these; bodies go to scratch files, never inline argv)

Each body is written to `$SCRATCH/<name>.md` with a quoted heredoc. The fenced blocks below are the
exact text. Each is posted with `--body-file`.

**Write protocol (applies to every task in Phase 2):**

- **Re-read before writing.** Before each write, run `gh issue view <N> --json state` and confirm it is `OPEN`. For 2.4 and 2.5, also read the labels that write changes.
- **Re-read #8660.** Before 2.2, 2.3 and 2.6, run `gh pr view 8660 --json state,mergedAt`. If it has merged, reword "after #8660 merges" and the `stage:"app_zot"` = 0 claim first.
- **Idempotency.** Every scratch body ends with the hidden marker `<!-- zot-records-2026-09-23:<N> -->` followed by a newline. Skip the post if `gh issue view <N> --json comments --jq '.comments[].body'` already contains it. This includes the two short follow-up notes in 2.7 and 2.8, which go through scratch files too (never inline `--body`).
- **Body edits (2.7, 2.8).** Replace with python `str.replace` after asserting `body.count(old) == 1`. The anchors contain `…` (U+2026) and backticks, so sed is unsafe. A body that already has the new text and no old anchor is already applied: treat it as a no-op success.
- **Label and milestone edits (2.4, 2.5).** `gh issue edit` exits 0 even when a removed label is absent, and a multi-flag edit can apply partly. After the edit, assert with a piped `jq -e`, not `gh --jq`, which has no `-e`. A non-zero exit stops the phase.
- **Post success.** `gh issue comment` exits non-zero on failure. Exit 0 plus the marker being present is the proof it landed. Keep the URL it prints.

**2.1 #7077 — evidence comment, then close.** Post this with `gh issue comment 7077 --body-file "$SCRATCH/7077.md"`, then run `gh issue close 7077 --reason completed`. The closure does not depend on this PR's diff, so it is not routed through a PR-body keyword:

```markdown
Verified against `main` @ fa1e2c8733 on 2026-09-23. All three acceptance items hold. Closing as completed.

**1. The mirror is not gated on the bridge outcome, and a bridge failure reaches the emitter and the Slack line. DONE in #7252 (merged 2026-08-04, 636a68aee7).** That diff removed the live `if: steps.zot_bridge.outcome == 'success'`.
- `.github/workflows/build-inngest-bootstrap-image.yml`: step `id: zot_mirror` has no `if:` (see its comment "NO `if:` — deliberately"). The bridge result arrives as `env: BRIDGE_OUTCOME: ${{ steps.zot_bridge.outcome }}` (outcome, not conclusion) and is branched on inside the script: `if [ "${BRIDGE_OUTCOME:-}" != "success" ]; then degraded bridge_down …`.
- `degraded()` writes `mirror_status=degraded` and `mirror_reason=` to the same step id. The Slack step is gated `if: ${{ !cancelled() && steps.zot_mirror.outputs.mirror_status == 'degraded' }}`.
- Pinned by `apps/web-platform/infra/inngest-bootstrap-mirror-only.test.sh` (run by `infra-validation.yml`). Its checks include "zot_mirror is NOT gated on the bridge outcome (a skipped step cannot emit)", "the bridge result reaches the script as OUTCOME, not conclusion" and the literal `if [ "${BRIDGE_OUTCOME:-}" != "success" ]; then` condition.

**2. The bridge probe proves the stream reaches zot. The property holds; the proposed mechanism is not being built.** The `nc -z 127.0.0.1 5000` loop in `.github/actions/cf-tunnel-registry-bridge/action.yml` is still a listener-only check. What it was meant to prove is now proven another way, on all five callers:
- Four callers leave `skip-docker-login` unset: `reusable-release.yml`, `build-inngest-bootstrap-image.yml`, `build-inngest-config-bundle.yml` and `apply-web-platform-infra.yml`. The composite's own `Docker login to zot` step dials zot's `/v2/` through the tunnel. A dead path fails that step, so the composite's outcome is `failure`. For this workflow, item 1 then routes that to `degraded bridge_down`. The cloudflared log is dumped at that step (FR-B2). A failed login can also mean a bad `ZOT_PUSH_*` credential rather than a dead path, so it is not a pure transport signal. Either way the failure lands on the bridge, not a later step, which is the property asked for.
- One caller sets `skip-docker-login: 'true'`: `registry-zot-inventory.yml` (#7278). It opens with its own explicit origin check (`scripts/zot-inventory.sh`, "B2 — origin reachability FIRST").
- Why the issue's mechanism is not being added: a probe that aborts inside the composite would bring back the abort that #7278 avoided on purpose for the inventory caller, which has to run *during* zot restart loops. The precondition "after a real release has exercised it from a runner" has been met since 2026-07-30, by every release.

**3. A recorded decision on the inngest host's pull path. DECIDED and BUILT in #7516 (merged 2026-08-13, 5c85b1c3e9); ADR-096 amendment 2026-08-13 "the inngest cold-boot pull site is migrated, by BAKE not Doppler".** `apps/web-platform/infra/cloud-init-inngest.yml` resolves a zot-primary digest ref (`ZIREF=…`) and falls back to GHCR. On 2026-09-23 at 19:37:18Z a boot logged `inngest_zot bootstrap image served by zot ep=10.0.1.30:5000` (see the #6122 comment of that date). The boot-time GHCR login that remains is #8036 item 1d scope, not this issue's.

Ref #7071, #6416, #6122.
```

**2.2 #8036 — 1d sequencing record.** Post this with `gh issue comment 8036 --body-file "$SCRATCH/8036.md"`:

```markdown
**Item 1d sequencing (recorded 2026-09-23): after PR #8660 (#8651) merges. Not before, and not in PR #8666.**

1d = retire the boot-time `docker login ghcr.io` (defined in the 1c plan's Non-Goals: "Retire cloud-init's boot-time `ghcr_login` … deferred to a tracked follow-up"). Every 1d site collides with #8660:

| 1d site | Collision with #8660 |
|---|---|
| `apps/web-platform/infra/cloud-init.yml` fresh-boot `ghcr_login` + seed pull | #8660 edits this file |
| `apps/web-platform/infra/soleur-host-bootstrap.sh` `STAGE=ghcr_login` / `ghcr_login_warn` | pinned by `soleur-host-bootstrap-observability.test.sh`, which #8660 edits. The script is also in `server.tf` `local.host_script_files`, so any edit moves `host_scripts_content_hash`. `apps/web-platform/infra/scripts/host-image-coherence-preflight.sh` checks that hash against the pinned image's baked host-scripts, so the edit would fail the replace job's preflight against web-1's running image. #8660's ADR-096 amendment says this: it does not "change any host-script (that would break the replace job's coherence preflight against web-1's running image)". |
| `apps/web-platform/infra/cloud-init-inngest.yml` boot `docker login ghcr.io` | pinned by `cloud-init-inngest-bootstrap.test.sh`, which #8660 edits. Separately, `hcloud_server.inngest` carries **no** `ignore_changes=[user_data]` (`inngest-host.tf`, "APPLY BEHAVIOR"), so any edit to this file replaces the dedicated inngest host on the next apply that targets it. 1d needs its own planned inngest replace. |

1d also removes the fresh-boot pull's only non-zot arm. Until #8660 proves a zot-served fresh web boot (`stage:"app_zot"` has 0 events to date), that arm is the only thing a fresh boot has, even though the credential it presents is revoked.

**Order:**

1. #8660 merges.
2. Its `web-fresh-boot-zot-8651` follow-through PASSes.
3. 1d lands in its own PR. It carries a fresh image build and pin (it moves the host-script hash) and a planned inngest-host replace (it changes that host's `user_data`).
4. #6410 closes as won't-fix-superseded (see #6410).

The Terraform and Doppler side of 1d cannot go early either. The boot sites still read `GHCR_READ_TOKEN`.
```

**2.3 #6410 — supersession condition (stays open).** Post this with `gh issue comment 6410 --body-file "$SCRATCH/6410.md"`:

```markdown
**Close condition recorded 2026-09-23: this closes as won't-fix-superseded when #8036 item 1d lands.** It stays open until then.

- The running-host contract this issue asked to mirror no longer exists. #8036 item 1c (PR #8600, merged 2026-09-23) deleted `_ghcr_pull_or_recover`'s GHCR leg and the relogin helper from `ci-deploy.sh`.
- 1d retires the boot-time `ghcr_login` itself, which is the "zot retires the GHCR boot pull first" condition in this issue's own "Re-evaluate when". 1d is sequenced after PR #8660 (#8651). See #8036.
- The login-ok/pull-deny class does not apply to a zot-primary boot. The fresh-boot zot pull uses the baked `ZOT_PULL_*` htpasswd credential, not a GHCR PAT.
```

**2.4 #6073 — decision: close as answered.** The question ("can an App installation token pull
private repo-linked GHCR packages?") was answered **no** on 2026-07-06, and the decision that
followed has been carried out. The p0 label is an SLA-bot escalation on an `action-required`
label. It is not a real priority. Relabelling would leave a tracker open with no action left, so
the issue is closed.

```bash
gh issue view 6073 --json state,labels --jq '.state, [.labels[].name]'   # re-read first
gh issue comment 6073 --body-file "$SCRATCH/6073.md"
gh issue edit 6073 --remove-label "priority/p0-critical" --remove-label "action-required"
gh issue view 6073 --json labels | jq -e '[.labels[].name] | (index("priority/p0-critical")==null) and (index("action-required")==null)'
gh issue close 6073 --reason completed
```

`action-required` is removed as well, so the SLA cron (`apps/web-platform/server/inngest/functions/action-required-sla-policy.ts`, which re-adds p0 at `minAgeDays: 60`) has nothing left to escalate.

`$SCRATCH/6073.md`:

```markdown
**Answered. Closing.** A GitHub App installation token **cannot** `docker pull` private repo-linked GHCR packages. `docker login` with the token succeeds but `docker pull` returns `denied`, and GitHub staff confirmed it in community discussion #171423 (recorded 2026-07-06 in `knowledge-base/project/learnings/2026-07-06-ghcr-app-token-cannot-pull-and-oidc-needs-native-identity-source.md`). ADR-096 records it in its header: `Supersedes: ADR-088 (… GHCR refuses App tokens for docker pull, confirmed platform limitation)`.

The decision taken on 2026-07-06 has been carried out. Production moved to self-hosted zot (#6122). The first zot-served pull was 2026-07-17T19:51:49Z, and zot has been the sole pull path since about 2026-07-29, when the interim PAT was revoked. No GitHub-support action is left. The `priority/p0-critical` label came from SLA escalation of the `action-required` label and did not reflect severity. Both labels are removed.

What remains of GHCR is tracked on #6122 (5.3b to 5.6) and #8036 (item 1d).
```

**2.5 #6122 — priority and milestone.** #6122 carries `priority/p2-medium` and milestone
`Post-MVP / Later`, while the two issues it waits on are P1: #6500 (`priority/p1-high`) and #8651
(`priority/p1-high`). A parent ranked below its own blockers drops out of any triage view ordered
by priority. It is also the epic for production's sole pull path.

```bash
gh issue view 6122 --json labels,milestone --jq '[.labels[].name], .milestone.title'   # re-read
gh issue edit 6122 --remove-label "priority/p2-medium" --add-label "priority/p1-high" \
  --milestone "Phase 4: Validate + Scale"
gh issue view 6122 --json labels,milestone | jq -e '([.labels[].name] as $l | ($l|index("priority/p1-high"))!=null and ($l|index("priority/p2-medium"))==null) and .milestone.title=="Phase 4: Validate + Scale"'
```

The milestone matches #8036's (`Phase 4: Validate + Scale`, an open milestone per
`gh api repos/jikig-ai/soleur/milestones`). No roadmap row is added. #6122 is not in
`knowledge-base/product/roadmap.md`, and this plan changes no roadmap phase table.

**2.6 #6122 — the ADR-169 against 5.3b write-up.**

1. Extract the section-4 fenced block mechanically, not by hand: `awk '/^## Decision needed: 5.3b/{p=1} p&&/^```$/{exit} p' <plan> > "$SCRATCH/6122-adr169.md"`.
2. Check that the extract is complete, with checks that can fail: `head -1` is the `## Decision needed: 5.3b` heading, `tail -1` starts with `- **B3:**`, and `grep -c '^```'` is `0`.
3. Append the idempotency marker.
4. Post with `gh issue comment 6122 --body-file "$SCRATCH/6122-adr169.md"`.

The comment ends with the bottom-line paragraph.

**2.7 #6630 — replace the dead close criterion.** Fetch the body with
`gh issue view 6630 --json body --jq .body > "$SCRATCH/6630-body.md"`. Make exactly two edits,
check them with `diff`, then post with `gh issue edit 6630 --body-file`:

- In step 2, replace `` emits `PRELUDE: docker login ghcr.io ok` / `ZOT_GATE: active … ok` `` with `` emits `ZOT_GATE: active — docker login … ok` (the only OK line since #8036 1c deleted the `PRELUDE: docker login ghcr.io` login; see `zot-login-gate-erofs-repaired-6565.sh`, "ONE-LEGGED SINCE #8036 1c") ``.
- Insert this directly above `**Re-eval by:**`:

  > **Amended 2026-09-23 (#8036 1c, PR #8600):** the close signal is the patched probe's. `scripts/followthroughs/zot-login-gate-erofs-repaired-6565.sh` must PASS: at least 2 distinct `_MACHINE_ID`s, each with at least one `ZOT_GATE: active … docker login … ok` line, and zero `class=cred_store` / `erofs` FAILED lines. A `PRELUDE: docker login ghcr.io` line can no longer be emitted and must not be waited for. Step 4's `apply_target=web-2-recreate` (and the `web2-recreate-preflight.sh` it names) was removed on 2026-07-20 (#6575). The probe PASS above is the close signal, not a recreate.

Both anchors were confirmed present exactly once in the live bodies on 2026-09-23: the step-2 text and `**Re-eval by:**` in #6630, and `## Scope` and the `From \`knowledge-base/project/brainstorms/…` line in #6427.

If either anchor is missing from the live body (someone edited it since 2026-09-23), stop and
comment instead of editing. Body edits do not notify watchers, so after the edit also post a
one-line comment through `$SCRATCH/6630-note.md` (marker `:6630-note`): "Close criterion amended
2026-09-23: the PRELUDE GHCR login line was deleted by #8036 1c (PR #8600); see the **Amended**
paragraph above Re-eval by."

**2.8 #6427 — narrow the scope.** Post a comment and edit the `## Scope` section. The history
above it stays.

- Fetch the body to `$SCRATCH/6427-body.md`.
- Replace the exact live span from `## Scope\n` up to, not including, `\n\nFrom \`knowledge-base/project/brainstorms/`. Today that span is 3 bullets. Replace it with the block below.
- The title stays. The narrowed `## Scope` and the note carry the change.
- Post with `gh issue edit 6427 --body-file`, then post a note through `$SCRATCH/6427-note.md` (marker `:6427-note`): "Scope narrowed 2026-09-23. See ## Scope: the ADR-096 and issue-alerts.tf text corrections landed in PR #6424, and 5.3a narrowed the rolling-deploy operand in PR #8600. The remaining scope is the 5.3b slice."

```markdown
## Scope (narrowed 2026-09-23)

- ~~Correct ADR-096's "load-bearing at Phase-5" claim and the `issue-alerts.tf` comment block~~. Done in #6285 / PR #6424 (merged 2026-07-15).
- ~~Re-point the soak and alarm off the rolling-deploy `ghcr-fallback` operand at 5.3~~. Done at **5.3a** (#8036 1c, PR #8600): the `registry:"ghcr-fallback"` emit site was deleted, the `zot_mirror_fallback_rate` rule was narrowed, and `zot-soak-6122.sh`'s `FAIL_QUERIES[rolling]` and its cardinality floor moved together.
- **Remaining, and blocked by 5.3b:**
  - **What the PR kills.** The PR that deletes the two `cloud-init.yml` fresh-boot GHCR branches kills `stage:"app_ghcr_fallback"` and `stage:"app_ghcr_served"`. `stage:"inngest_ghcr_fallback"` survives until `cloud-init-inngest.yml`'s GHCR leg also goes (the #8036 1d / inngest-replace slice).
  - **What the same PR must do.** Retire or re-point `zot-soak-6122.sh`'s `FAIL_QUERIES[appboot]` and `[appserved]` (and move the cardinality floor with them), and `[freshboot]` in whichever slice kills `inngest_ghcr_fallback`. Narrow the alarm's `filters_v2` in step.
  - **What it must not do.** Do not retire the alarm: `registry:"zot-gate-degraded"` (`[gate]`) is gate-emitted and survives, per ADR-096's "Do NOT retire the alarm at 5.3 — narrow its `filters_v2`".
```

### Phase 3 — Verification (work phase)

Run the Pre-merge Acceptance Criteria below. Also run the pinned `markdownlint-cli` (package.json)
with the repo's `.markdownlint.json` over the two edited files, and `bash scripts/check-adr-ordinals.sh`
(no ordinal is added).

## 4. ADR-169 against 5.3b deadlock (write-up for the operator; no option is chosen)

**Superseded 2026-09-24:** the write-up was revised after review and the posted comment is now the only copy:
https://github.com/jikig-ai/soleur/issues/6122#issuecomment-5803873046. The revision added an Option 0 (do nothing),
evened the per-option costs (the release-build re-plumb applies to A, B1 and B2; B2 needs a snapshot job and a
restore redesign), corrected the bottom line (below), and put two explicit questions to the operator.

## Files to Edit

- `knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md`: the `## Status` block only (lines 9-17). This does not overlap #8660's append at 1273+.
- `knowledge-base/project/specs/feat-registry-oidc-migration/tasks.md`: 1.8, 1.9 and 2.4 ticked with evidence (1.8 was planned as `[~]`; superseded, see DC1). 5.3 split into 5.3a (done) and 5.3b (open).

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-zot-migration-completion/tasks.md` (derived from this plan)

**Explicitly not edited:**

- `apps/web-platform/infra/cloud-init.yml`
- every file in #8660's list
- `soleur-host-bootstrap.sh` and `cloud-init-inngest.yml`
- the bridge composite and any workflow
- `zot-soak-6122.sh`: no re-arm, no `START` change

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (200 max) was checked on 2026-09-23 against the
ADR-096 path, `feat-registry-oidc-migration/tasks.md` and `ADR-096`. Zero matches.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing at runtime. This PR changes no executable
file. The only failure is an incorrect record. The worst case is a status or close criterion that
states the wrong gate, which could lead someone to authorize 5.3b early. Two things mitigate it:
the Status text names the gate as *pending* and quotes the FAIL, and section 4 decides nothing.

**If this leaks, the user's data / workflow / money is exposed via:** no new surface. The comments
cite public PR numbers, Sentry and Better Stack signal names and commit SHAs only. No credential
value, token prefix or host address is added. The one private IP already appears in the repo's
`cloud-init` and in the earlier #8037 comments.

**Brand-survival threshold:** none

- threshold: none, reason: records-only change (one ADR status block, one tasks.md, GitHub issue metadata); no code, infra, credential, or user-data path is touched.

## Acceptance Criteria

`$KW` is the GitHub closing-keyword extractor:
`\b(close[sd]?|fix(e[sd])?|resolve[sd]?)\b:? *((jikig-ai/soleur)?#|https://github\.com/jikig-ai/soleur/issues/)[0-9]+`
(case-insensitive). This PR closes nothing by keyword. #7077 and #6073 are closed directly in Phase 2.

### Pre-merge (PR)

- [x] **AC1 (exact allowlist).** `git diff --name-only origin/main...HEAD | grep -vxF -f "$SCRATCH/allowlist.txt"` prints nothing.
  - The allowlist is ADR-096, `knowledge-base/project/specs/feat-registry-oidc-migration/tasks.md`, this plan, and `knowledge-base/project/specs/feat-one-shot-zot-migration-completion/{tasks.md,decision-challenges.md,session-state.md}`.
  - It also includes `knowledge-base/INDEX.md`, but only if the pipeline regenerates it.
  - So no path under `apps/`, `.github/`, `scripts/` or `plugins/` can appear, `cloud-init.yml` included.
- [x] **AC2.** `awk '/^## Status/{p=1;next} /^## Amendment 2026-07-30/{p=0} p' <ADR-096>`:
  - contains each of these phrases: `2026-07-17T19:51:49Z`, `**sole** pull path`, `stage:"app_zot"`, `**5.3a**` and `pending** behind the #6122`
  - does not contain `inert until` (the unedited copy on `main` does, so this check is red before 1.1)
  - `git diff -U0 origin/main...HEAD -- <ADR-096>` shows exactly one `@@` hunk, and it starts at or before line 17
- [x] **AC3.** Each of these `grep -cE` checks over the registry-oidc `tasks.md` returns `1`:
  - `^- \[x\] 1\.8 ` (was `[~]`; superseded 2026-09-24 by live measurement, see DC1)
  - `^- \[x\] 1\.9 `
  - `^- \[x\] 2\.4 `
  - `^- \[x\] 5\.3a .*#8600`
  - `^- \[ \] 5\.3b `
  - `^- \[ \] 5\.[456] ` returns `3`
  - `git diff origin/main...HEAD -- <tasks.md> | grep -E '^-[^-]'` shows only the old 1.8, 1.9, 2.4 and 5.3 lines.
- [x] **AC4 (no keyword closure).** Both of these print nothing:
  - `git log --format=%B origin/main..HEAD | grep -oiE "$KW"`
  - `gh pr view 8666 --json title,body --jq '.title + "\n" + .body' | grep -oiE "$KW"`
  - Re-run both on the final title and body immediately before `gh pr merge`. The squash commit is built from them.
- [x] **AC5 (Phase 2 writes landed).** Each check reads live state:
  - Every comment in 2.1-2.8 exited 0, and its marker is present in `gh issue view <N> --json comments --jq '.comments[].body'`.
  - `gh issue view 7077 --json state,stateReason` and `gh issue view 6073 --json state,stateReason` both show `CLOSED` / `COMPLETED`.
  - `gh issue view 6410 --json state` is still `OPEN`.
  - The 2.4 and 2.5 `jq -e` asserts exit 0.
  - #6630's body contains `**Amended 2026-09-23` and `ZOT_GATE: active`, and no longer contains `PRELUDE: docker login ghcr.io ok`.
  - #6427's body contains `## Scope (narrowed 2026-09-23)`.
  - #6122's section-4 comment (revised 2026-09-24) contains `**Option 0`, `**Option A`, `**Option B1`, `**Option B2`, `**Option B3` and `### Questions for the operator`. `grep -ciE 'we recommend|we should|recommended option|prefer(red)? option'` over it prints `0`.
- [x] **AC6 (reserved acts untouched).** `git diff origin/main...HEAD -- scripts/` is empty, and `gh issue view 6500 --json state --jq .state` is `OPEN`. No task re-arms `zot-soak-6122.sh`, closes #6500, or performs 5.3b, 5.4, 5.5, 5.6 or #6129.
- [x] **AC7.** `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` exits 0. This is the gate's own invocation, not a hand-picked file list.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** The CTO reviewed the #7077 verdict, the 1d verdict, the section-4 write-up and the Status text. The #7077 verdict and the 1d sequencing are OK. Four changes were folded in:
- 1d also needs a planned inngest-host replace, because that host's `user_data` is not ignored.
- "Stop GHCR push" is not a toggle: buildx pushes to GHCR, and `crane copy` fills zot from GHCR.
- Option A's cost is qualified "if same type".
- The Status block names the unobserved zot fresh web boot.

The scoped advisor consult (Phase 4.5) produced DC1 and DC2. SpecFlow shaped the write protocol and the removal of `action-required`. The plan-review panel (DHH, Kieran, code-simplicity) cut the ceremony and corrected four facts:
- the preflight path
- the soak `FAIL_QUERIES` keys
- the emit sites that survive 5.3b
- B2 was missing from the bottom line

## Test Scenarios

This plan ships no executable change, so there are no unit tests. Each Pre-merge AC runs a command and has a negative control:

- AC1: a scratch path outside the allowlist is printed.
- AC2: the `main` copy of ADR-096 contains `inert until`.
- AC4: `printf 'Fixes https://github.com/jikig-ai/soleur/issues/6410\n' | grep -oiE "$KW"` matches.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. It is filled here with `none` and a reason.
- **Auto-close keywords reach commits too.** `wg-use-closes-n-in-pr-body-not-title-to`: a commit message saying "closes #6410 when 1d lands" would close #6410 on merge. Use `Ref #N` everywhere.
- **Do not "fix" #7077 item 2 by adding the probe.** It looks like an open acceptance box. It is covered, and adding the probe breaks #7278's inventory caller (see the Cut List).
- **Do not tick 5.3 whole, and do not touch 5.4, 5.5 or 5.6.** Only 5.3a is done, and it was done on the "no reachable success arm" ground, not on a soak pass.
- **Do not move `START` in `zot-soak-6122.sh`.** A late `START` is the documented false-PASS route. This PR does not touch `scripts/`.
- **#8660 may merge before this PR.** Its ADR-096 hunk is an append at the end of the file, so a rebase is conflict-free by construction. Re-run AC2's range check after any rebase anyway.
- **Issue bodies may have moved.** 2.7 and 2.8 do anchored text replacement. If an anchor is missing, comment instead of editing. Never overwrite a body that was not read in the same step.
- **This PR closes nothing by keyword.** #7077 and #6073 are closed directly in Phase 2. `soleur:ship` writes and replaces the whole PR body, so AC4's pre-merge re-check is what catches a stray `Closes`/`Fixes`/`Resolves` (including URL forms) that it or a commit introduces.
- **Fenced blocks here contain `## Status`, `## Scope` and `## Decision needed` headings.** Any scripted edit to this plan must anchor at line start and assert a match count of exactly 1. Otherwise it hits the fenced copy.
- **Keep the section-4 wording neutral.** The write-up must not rank the options. The costs and risks are stated per option, and the bottom line is the authorization act, not a recommendation.
