---
title: "chore: bump the zot pin to the current upstream and add docker.pkg.github.com to the hosts-file GHCR deny, as one registry-host user_data change"
date: 2026-10-08
slug: zot-pin-v2-1-22-and-docker-pkg-github-deny-registry-replace
branch: feat-one-shot-9252-zot-pin-bump-ghcr-deny
issue: 9252
type: chore
priority: p3-low
domain: engineering
lane: cross-domain
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
pr: 9795
---

# chore: zot pin bump + docker.pkg.github.com hosts-file deny, one registry-host replace

## Enhancement Summary

**Deepened on:** 2026-10-08
**Method:** plan-review panel (DHH, Kieran, code-simplicity, CTO devex); deepen-plan gate sweep (4.5 to 4.12); targeted agents (architecture-strategist, spec-flow-analyzer, observability-coverage-reviewer, terraform-architect); live re-verification of every cited state, run, path and number. Not run: the full 40-agent fan-out and per-learning sub-agents (an infra chore with every claim checkable by command; the learnings pass was done once by the learnings researcher).

### Key improvements
1. Squash-message behaviour of the merge queue was verified from merged commits `fd1c4d5cac` and `3ed3e4e6da` instead of assumed; the kill-switch lines must sit in a commit BODY.
2. Kieran's P1: `ci-deploy.test.sh` is a third staleness-check-7 follower and would have reddened CI; added, with two further version-scoped claims (`zot-fill-rate-7341.sh`, `reusable-release.yml`) recorded.
3. Upstream zot#4235 is closed and its fix (#4236) is in v2.1.21+, so the follow-through that waits on it needs rewording and its outcome is read in the soak.
4. Observability failure modes now cite layers and stop claiming alerts that do not exist (no Better Stack alert on `zot_image_fetch` not ok); `## Failure Branches` covers mirror-dispatch, queue ejection, missing dispatcher run, `deliver=false`, PR 9783 ordering, and holding other infra PRs; the `ci-deploy.sh` edit also reaches `deploy_pipeline_fix` (web-1), so D1 now names it; the web gzip budget is checked.
5. Added the `## Downtime & Cutover` and `## Encryption Posture` sections the deepen gates require; cut Guard 2 and the ADR-169 / runbook edits (simplification panel); added timebox, push-apply-fires-anyway protocol, numeric soak, rollback decision rule.

### New considerations discovered
- `ghcr_blocked` probes ghcr.io only; the third name is proven by R10 and the render diff, not by telemetry.
- The 12-hourly drift run will report `triggers_replace` drift for web-1/web-2 after the kill-switched merge.

## Overview

Two open issues each change a render input of the registry host's `user_data`, so they ship as one
change and one delivery. Issue 9252 moves the zot image pin in `zot-registry.tf` (the ubuntu half of
that issue is a different PR and is not in this one). Issue 9390 adds a third name to the hosts-file
deny that the registry runcmd entry writes. Both force the registry host through a destroy-first
`registry-host-replace`; bundling them means the sole pull path goes through one outage window, not two.

The delivery is the existing `registry-host-replace-dispatch.yml` push arm, which fires on merge. This
plan adds no workflow, no new gate and no new probe. The work is: a pin bump that follows the sidecar's
Bump procedure, a deny edit at every byte-identical site, and a delivery runbook that says what each
gate means and what to do when one is red.

Live state at plan time (2026-10-08, read, not assumed):

- upstream zot latest is `v2.1.22` (published 2026-10-06T16:50Z); pinned is `v2.1.20`.
- `apply-web-platform-infra.yml` and `apply-deploy-pipeline-fix.yml` both read `active` (updated
  2026-10-08T19:07Z); the registry dispatcher reads `active`. The earlier "paused" prose in ADR-169's
  2026-10-03 amendment and `cron-egress-blocked.md` is superseded by today's state. A merge therefore
  fires BOTH push applies (they reach web-1 and web-2 over SSH) AND the registry dispatcher.
- `scripts/registry-replace-preflight.sh` run read-only against production reads
  `verdict=CLEAR local_cache_hits=0 ghcr_fallback_hits=0 in_progress_releases=0 obs_control_hits=200
  obs_channel_hits=200` for the current pin's asset.
- PR 9783 (the ubuntu:24.04 base-pin half of #9252) is still OPEN, not merged.

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality (checked) | Plan response |
|---|---|---|
| "the ubuntu:24.04 half is already shipped by a separate PR" | PR 9783 `chore(infra): bump the ubuntu:24.04 base pin in the git-data rehearsal` is OPEN | PR body uses `Ref #9252`, never a closing keyword. No ubuntu edit here. |
| Apply workflows paused (ADR-169 amendment 2026-10-03, runbook prose) | Both `active` since 2026-10-08T19:07Z; apply runs succeeded today | Merge-time web-host contact is real. Decision D1 below (kill-switch lines) reconciles it with "do not touch web-1". |
| "rehearsing with plan_only first where the path supports it" | `plan_only` is declared for `web-host-replace` and `git-data-host-replace` only; the `registry_host_replace` job has no `plan_only` conjunct | No `plan_only` rehearsal exists for this path. Substitutes: offline render diff, PR-time `rehearse` x3 stores, local read-only preflight. Not adding `plan_only` (would edit a workflow: no admin-merge path, byte budget). |
| #9390 lists six byte-identical sites | A seventh carries the deny literals: `cloud-init-ghcr-seed-login.test.sh` (`DENY_HEADER`, `DENY_BLOCK`, `DENY_HDR`, mutation rows 16c/17/18) | Added to Files to Edit (inferred, justified in Scope Check). |
| Step 3 "re-diff the four upstream anchors" is the compatibility analysis | v2.1.20 to v2.1.22 is 128 commits, one breaking (`fix(api)!` #4363, in v2.1.21). Measured against this repo's exact config: HEAD of a blob that exists only under another repo is 200 on v2.1.20 and 404 on v2.1.22; `POST ?mount=` unchanged. Also the distSpec WARN now fires (config 1.1.0, supported 1.1.1) | Added step 3b (breaking-change scan) to this bump and to the sidecar's Bump procedure. |
| Previous known-good pin format | Staleness check 8 parses `zot-linux-<arch>@sha256:<64hex>` (tag-less) in `## Previous known-good pin` | Rotate in that exact shape; also record v2.1.20's T, C and release tag so rollback needs no git archaeology. |
| Step 5 "publish the boot asset via zot-image-mirror.yml BEFORE the bump merges" | The builder reads D from the checked-out `zot-registry.tf`; a branch dispatch builds whatever the branch pins | Commit the new `zot_image_*` locals and push BEFORE dispatching; pin T and C in a second commit. |
| "a PR touching .github/workflows has no agent admin-merge path" | The planned diff touches no `.github/workflows/*` file | Stated as an AC; ordinary merge-queue path. |

## Research Insights

**Premise validation (Phase 0.6).** Held: #9252 and #9390 OPEN; draft PR 9795 OPEN; the dispatcher, preflight
script, ADR-169 amendments and the runbook exist on `origin/main` (`d0b5d2e35b`). Stale: "ubuntu half
shipped" (PR 9783 open); "paused" apply workflows (active); "plan_only where supported" (unsupported on
this path); #9390's six-site list (seven). The mechanism was checked against the ADR corpus: ADR-096
(amendment 2026-09-28 part 2) and ADR-169/190 already decide the boot-asset design and the replace
authorization, so no decision here is new.

**Property List (Phase 0.6b).**
1. After the replace, the registry host runs zot at the current upstream pin, booted from a published, digest-verified asset.
2. The host-process hosts-file deny covers docker.pkg.github.com, and every byte-identical copy still equals the registry's entry.
3. Nothing is bypassed and no host other than the registry is replaced (store volume preserved).
4. The new host is shown healthy from telemetry, with no SSH.
5. The rollback target for the superseded pin survives the bump.

**Cut List.**
- `plan_only` for the registry job: P3 is already covered by the dispatcher gate, preflight, and the apply job's own plan-shape and stock gates.
- A new follow-through probe: P4 is covered by `SOLEUR_ZOT_DISK` rows read with `scripts/betterstack-query.sh`.
- A per-name `ghcr_blocked` probe for docker.pkg.github.com: no property needs it; R10 executes the rendered entry and `ghcr_blocked=1` proves the same loop ran.
- A second, manual dispatch of the replace: the merge-fired dispatcher is the route; a second one is the double-replace hazard.
- Adopting `hydrateBlobOnRead`, `distSpecVersion` 1.1.1, `FastRestart`, `keepUntagged`: config JSON stays byte-unchanged unless step 3b hits its STOP rule.
- A new ADR: no new decision; dated amendment lines only.

**Measured at plan time (re-measure at work time; these are pre-readings, not the record).**
- Digests (anonymous ghcr.io token, same method reproduces the v2.1.20 pins): amd64 v2.1.22 `sha256:46f688dc26315a35a247e1784368829e66a67bf91de94c7d8d1645044fac1d5b`, arm64 v2.1.22 `sha256:920e3e327a73513643c67d14f54092c45ece6d29660bff7e898107e00b49fa03`. amd64 manifest `.config.digest` (C): v2.1.20 `2d7fee56...` (matches the pin), v2.1.22 `sha256:5a8db63c9fae93403c39376052e205c41a469dbd84b3d1ea37ee497cb08318ef`. D12 for telemetry: `46f688dc2631`.
- Four anchors v2.1.20 vs v2.1.22 (source at the tags): `func updateDistSpecVersion` IDENTICAL; `type RetentionPolicy` IDENTICAL; `type KeepTagsPolicy` IDENTICAL; `type AccessControlConfig` IDENTICAL; `GlobalStorageConfig` and `HTTPConfig` IDENTICAL; `pkg/compat/compat.go` `DockerManifestV2SchemaV2 = "docker2s2"` unchanged, two additive helpers (`IsImageManifestMediaType`, `IsImageIndexMediaType`).
- Claim 1 (200 or 401, never 403), exact `config.json` from `cloud-init-registry.yml` with synthetic users and bcrypt htpasswd, both pinned digests, local docker: anon `/v2/` 401, pull user 200, push user 200, bad password 401, missing repo 404; zero 403. Claim 2 (no on-demand gc endpoint): `/v2/_zot/gc`, `/v2/_catalog/gc`, `/_zot/gc`, `/v2/_zot/ext/gc` all 404 on both. v2.1.22 emits `level":"warn"` for `config dist-spec version differs` (1.1.0 vs 1.1.1) and zero error/fatal lines, so the `zot_last_err` error/fatal tiers are not tripped.
- #4363 effect: HEAD `repob/blobs/<digest>` for a blob uploaded only to `repoa`: v2.1.20 200, v2.1.22 404; `POST repob/blobs/uploads/?mount=<digest>&from=repoa` 201 on both and HEAD then 200. `storage.dedupe` is `true` in the deployed config, so this applies. CI pushes with `crane copy` GHCR to zot (cross-registry: no mount path), so a layer shared by two zot repos is uploaded again instead of skipped. Slower, not broken; bounded by the 1800 s deadlines ADR-190 sized.
- Full preflight against production, read-only, from this worktree (see overview): CLEAR.
- Budget: `registry-userdata-budget.sh --json` stored 20,932 B, cap 32,768, headroom 11,836 B. Three names add tens of bytes.

**Other v2.1.21/22 commits read against this config** (full list: `gh api repos/project-zot/zot/compare/v2.1.20...v2.1.22`):
#4318/#4236/#4351/#4325/#4383 (gc/dedupe/walk changes: covered by the soak after the replace, not by a unit measurement); #4447 (digests stay pullable after last-tag overwrite: retention semantics, additive); #4419 (skip `lost+found` in storage walks: the ext4 store root carries one); #4285 (htpasswd hot-reload: the measured 200/401 matrix covers file-mounted htpasswd); #4380 (dedupe mount auth enforced); #4414 (HSTS on TLS responses: the host serves plain HTTP behind the tunnel, n/a); #4307 (sigstore v3 bundle recognition: cosign path, additive).

**Institutional learnings applied.** `2026-09-30-my-deny-guards-proved-one-template-arm-and-missed-one-line-blocks` (parity must be rendered on BOTH `web_tunnel_connector` arms); `test-failures/2026-10-06-which-files-feed-user-data-...` (`hcloud_server.registry` has no `ignore_changes=[user_data]`; sibling suites pin edited lines by text: `web-ghcr-deny.test.sh`, `cloud-init-user-data-size.test.ts`, `ci-deploy.test.sh`); `2026-07-26-cloud-init-comment-is-a-live-host-input-...` (a comment is only inert because the render strips it: assert the render diff, do not assume); `2026-06-02-auto-merge-livelock-fast-moving-main` §merge queue (never sync a queued PR); vector-redeliver runbook (a kill-switch line counts only in a branch COMMIT message, never the PR body).

## User-Brand Impact

- **If this lands broken, the user experiences:** a registry host that boots dark: running web containers keep serving, but every deploy (including security fixes) fails at the pull step until the host is restored, and a fresh web-host boot fails at its pull stage.
- **If this leaks, the user's data is exposed via:** no data path changes. The change moves a public image pin and adds a blocked hostname; no credential, no user data and no store content is touched (the zot store volume is preserved).
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** not `single-user incident` because no user data or per-user workflow is exposed; not `none` because a failed destroy-first replace under a Hetzner stock shortage can freeze deploys fleet-wide for hours (#6393 precedent), which is an aggregate availability pattern.

## Hypotheses

This plan diagnoses no connectivity symptom, so the L3-to-L7 layers have nothing to verify; each is recorded so the gate's intent is visible. The keyword that triggered the gate is "no SSH": it names an exclusion, plus the SSH `remote-exec` provisioners that consume copy B (below).

- L3 firewall allow-list: not applicable. No new network path is opened; the deny closes a name. The Hetzner firewall carries inbound rules only and is not edited.
- L3 DNS and routing: not applicable to an outage; the deny is a name-resolution sinkhole by design. The one resolution fact that matters is asserted by copy B's own post-deny `getent ahosts` check on the web routes.
- L7 TLS and proxy: not applicable. The registry is reached over the private network and the Cloudflare tunnel; neither is edited.
- Service layer: the SSH provisioners that consume `local.ghcr_deny_sh` (`zot_consumer_probe_install` on web-1, `deploy_pipeline_fix_web2` on web-2) are the only SSH dependency this change creates. Decision D1 keeps the merge from firing them.

## Open Code-Review Overlap

One open scope-out names a planned file path: #2197 (billing `SubscriptionStatus` type refactor), whose body mentions `apps/web-platform/infra/server.tf` incidentally. Acknowledge: unrelated concern (billing types), stays open.

## Files to Edit

Infra (`apps/web-platform/infra/`):
- `zot-registry.tf`: `zot_image_amd64`, `zot_image_arm64` (v2.1.22 + both digests); `zot_mirror_asset_sha256_amd64` (T); `zot_config_digest_amd64` (C).
- `zot-image.provenance.md`: header table, `## Current pin`, `## Previous known-good pin` (rotated, tag-less, plus v2.1.20 T/C/release tag), `## Why v2.1.22` (floor stays v2.1.19), config-compatibility table (re-diffed), non-adoption list, version-scoped claim register (dates), new Bump-procedure step 3b, capture date.
- `cloud-init-registry.yml`: copy R (third name); comment claims that name `zot v2.1.20` (three places) re-measured and re-dated.
- `cloud-init.yml`: copy A.
- `server.tf`: `local.ghcr_deny_sh` and `local.ghcr_deny_assert_sh` (copy B).
- `ci-deploy.sh`: comment-only: the `zot v2.1.20 ... MEASURED 2026-08-05` claim block above `_docker_login_failure_class`.
- `ci-deploy.test.sh`: the "401 fixture is byte-accurate - reproduced against the pinned zot v2.1.20" comment (staleness check 7 follower; re-measure the 401 fixture against the final digest before re-dating it).
- `scripts/followthroughs/zot-fill-rate-7341.sh`: header and FAIL message say "zot#4235 is unfixed in v2.1.20"; upstream #4235 is CLOSED and its fix PR #4236 merged 2026-08-11 (in v2.1.21+), so after the replace the sentence is false. Reword to the measured state; no logic change.
- `web-ghcr-deny.test.sh`: `HDR`, getent shim (third name), exec/agree/census rows, mutation rows.
- `zot-image-fetch.test.sh`: R5 header literal, R10 counts (hosts file 5 lines becomes 7; per-name counts), the `v2.1.20` fixture string.
- `cloud-init-ghcr-seed-login.test.sh`: `DENY_HEADER`, `DENY_BLOCK`, `DENY_HDR`, mutation rows that embed the header.
- `zot-image-staleness.test.sh`: only if a count or comment names the version (read first; the floor `MIN_ASSERTIONS` is not lowered).

Docs:
- `knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md`: dated amendment line (deny now names three hosts).
- Not edited (plan review cut them): ADR-169's 2026-10-03 amendment and `cron-egress-blocked.md` carry stale "paused" prose, but the toggle is not owned by this PR; the PR body records the 2026-10-08 `active` observation instead.

## Files to Create

None in product code. The pipeline artifacts `knowledge-base/project/specs/feat-one-shot-9252-zot-pin-bump-ghcr-deny/tasks.md` and `decision-challenges.md` are created by the plan phase and already committed.

Not touched, by instruction: `.github/workflows/*`, `.mcp.json` (pre-existing local modification: stage explicit paths only), `git-data-runcmd-rehearsal.test.sh` (ubuntu half), anything for web-1, web-2, git-data.

## Implementation Phases

TDD order inside each phase: tests that name the new value go RED first (`cq-write-failing-tests-before`), then the edit.

### Phase 0 — Preconditions (read-only)

- Confirm `git branch --show-current` is the feature branch; `git fetch origin main`; no tracked modifications other than possibly a stray `.mcp.json` (never stage it).
- Re-read: `gh api repos/jikig-ai/soleur/actions/workflows/<file> --jq .state` for the three workflows; `gh release list -R project-zot/zot --limit 3` (latest may have moved past v2.1.22: if so, redo steps 2 to 6 for the new tag and say so in the PR); `gh pr view 9783 --json state`.
- Baseline: the suites for the files being edited (AC1, AC7) are green on the untouched tree.

### Phase 1 — Rotate the previous-known-good pin, then resolve both digests (prerequisites 1, 2)

1. In `zot-image.provenance.md` `## Previous known-good pin`, replace both rows with the v2.1.20 refs in the tag-less shape the staleness check parses: `ghcr.io/project-zot/zot-linux-amd64@sha256:95a837a0...fd5 (v2.1.20)` and `...arm64@sha256:56230c5a...ff6 (v2.1.20)`, superseded 2026-10-08. Add a line with the v2.1.20 boot-asset facts: release `zot-image-v2.1.20-95a837a0afac`, T `05b171f2bd500dc84f532ef7736d1550ffaf7464f0d655c86b8238b443568cb2`, C `2d7fee5603dfd88b2b90cffd07e6b97e6d7ba5e3d6bd5472e66b23bd5ad59114` (that release is immutable and published; P6 reads CLEAR for it today).
2. Resolve with `crane digest` (or the anonymous-token curl used at plan time, which reproduced the v2.1.20 pins) for BOTH `zot-linux-amd64` and `zot-linux-arm64` at the target tag. Never one arch. The two digests must differ.
3. Edit `zot_image_amd64`, `zot_image_arm64` in `zot-registry.tf` and `## Current pin` together. Commit A (pin locals + rotation). Push the branch.

### Phase 2 — Anchors, claims, breaking-change scan (prerequisites 3, 4)

3. Re-diff the four anchors v2.1.20 to the target tag from upstream source (not release notes). Update the config-compatibility table with a verdict per anchor. Pre-reading: all identical, `compat.go` additive.
3b. Breaking-change scan: list commits between the tags whose subject carries `!:` or `BREAKING`; for each, read the PR body and decide whether it touches a surface this config uses. #4363 does (`dedupe: true`). Re-run the plan-time measurement (two repos, upload to one, HEAD/mount against the other, on both pinned digests) and record the result in the config-compatibility table. Add one line to the sidecar's Bump procedure ("scan `!:`/BREAKING commits between the tags") and nothing more. Shared-layer question, one question only: does any layer that two zot repos would share exceed what the `crane copy` retry/deadline window in `reusable-release.yml` can re-upload (ADR-190 sized the server deadline at 1800 s)? STOP rule, limited to what is testable before merge: if that answer is yes, or the same-repo HEAD, push or pull matrix differs between the two versions, stop, record it, and do not mark ready; the fix would be `storage.hydrateBlobOnRead: true` (a config JSON change: `registry-boot-guard.test.sh` fragments and a fresh decision), not part of this plan. gc/retention behaviour is covered by the post-replace soak (see Delivery Runbook), not by this rule. Otherwise `hydrateBlobOnRead` is recorded NOT ADOPTED, with the measured reason, in the sidecar only.
4. Re-measure the two version-scoped claims by running the pinned image locally with this repo's exact `config.json` (extract the `/etc/zot/config.json` block from `cloud-init-registry.yml`, substitute synthetic users for `${zot_pull_user}` / `${zot_push_user}`, bcrypt htpasswd) and probing `/v2/` for 200-or-401 and the four gc paths for 404. If any 403 appears: STOP, downgrade the claim to `UNMEASURED`, file an issue, do not ship the comment. Update the three `zot vX.Y.Z` comment sites in `cloud-init-registry.yml`, the block in `ci-deploy.sh` and the comment in `ci-deploy.test.sh` to the target tag and the new measurement date (staleness check 7 reads all three followers). Unregistered version-scoped claims, listed in the sidecar's claim register so the next bump finds them: `.github/workflows/reusable-release.yml` ("zot v2.1.20's built-in ReadTimeout/WriteTimeout", a default that the explicit 1800 s config overrides; the file is a workflow and is left alone) and `scripts/followthroughs/zot-fill-rate-7341.sh` (reworded here). Confirm the scraper still matches the v2.1.22 log shape (`"level":"error"` form) and note the new distSpec WARN is warn-level.
6. Re-stamp `Capture date (UTC)` only after steps 2 to 4 are done; run `zot-image-staleness.test.sh` (must exit 0) and `zot-image-staleness-mutation.test.sh`.

### Phase 3 — Publish the boot asset BEFORE the bump merges (prerequisites 5, 6)

Ordering constraint (between a workflow dispatch and a PR merge, spelled out):

```text
commit A (new zot_image_* locals) pushed to the branch
  -> gh workflow run zot-image-mirror.yml --ref feat-one-shot-9252-zot-pin-bump-ghcr-deny
  -> publish job: builds from upstream D (the branch's pin), creates release zot-image-<ver>-<D12>
     as a DRAFT prerelease, uploads the asset, publishes it (immutable from here); prints PUBLISHED_T
  -> rehearse job (3 stores) boots the published asset
  -> pin T = PUBLISHED_T and C = manifest .config.digest in the zot-mirror block; commit B; push
  -> PR CI rehearse rebuilds from upstream D and must reproduce T and C
  -> ONLY THEN may the PR be marked ready / enqueued
```

Why it cannot be later: after the merge, the dispatcher's preflight P6 (and the apply job's own P6) refuses a replace whose asset is unpublished, so a merge-first order produces a `refused` verdict and an unreplaced host that nothing re-fires by itself. Why it cannot be earlier than commit A: the builder reads D from the checked-out `zot-registry.tf`.

- The publish is irreversible and harmless if the PR is abandoned: `zot-image-*` releases are never deleted and are not "latest".
- Read T from the run summary (`published T`) via `gh run view <id> --log | grep PUBLISHED_T`. If the workflow warns that the published sha256 differs from its own rebuild, STOP before pinning: the PR `rehearse` rebuilds on the same runner label and requires its rebuild to equal T, and the release is immutable, so a mismatch would leave it permanently red. Investigate reproducibility (tar version, runner image) first and report.
- Verify with `GH_TOKEN="$(gh auth token)" bash scripts/registry-replace-preflight.sh --check-asset` on the branch: must print `verdict=CLEAR predicate=P6` naming the new asset.
- Only the `publish` job of the dispatch matters at this point; its own `rehearse` job runs against T and C values that are still v2.1.20's, so it is expected RED, as are the PR's `rehearse` jobs and staleness check 7 (claims still naming v2.1.20) between commit A and the final commit. That is the ordering, not a defect.

### Phase 4 — The hosts-file deny at every site (prerequisite 7)

Target shape: the loop header becomes `for h in ghcr.io pkg-containers.githubusercontent.com docker.pkg.github.com; do`, appended last so the existing leading literal stays a prefix. Everything else in the entry is byte-unchanged.

7. Tests first (RED): `web-ghcr-deny.test.sh` (`HDR`, getent shim case for the third name, exec expectation of 3 names x 2 lines, agree rows, census), `zot-image-fetch.test.sh` (R5 literal; R10: hosts file `localhost` + 6 lines = 7, per-name once each, template line count), `cloud-init-ghcr-seed-login.test.sh` (`DENY_HEADER`, `DENY_BLOCK`, `DENY_HDR` and the rows that splice the header).
8. Edit copy R (`cloud-init-registry.yml` runcmd entry), copy A (`cloud-init.yml` runcmd[1]), copy B (`server.tf` `ghcr_deny_sh` loop and `ghcr_deny_assert_sh` loop). All three loops get the same three names in the same order. Run `web-ghcr-deny.test.sh` on both `web_tunnel_connector` arms (the suite does).
9. Sweep for any other literal: `git grep -n "for h in ghcr.io"` and `git grep -n "pkg-containers.githubusercontent.com" -- ':!knowledge-base/project'` and disposition every hit (the `cron-egress-*` and Sentry hits are the separate #9275 bridge layer: not touched).
10. Size and render gates: the AC8 suite list (registry headroom stays above 10 kB; baseline 11,836 B). Web arm too: copy A adds about 22 raw bytes to the web render, whose gzip headroom was recorded as about 28 B after #9169 (`server.tf` comment) against `WEB_GZIP_BUDGET` 23,800 in `plugins/soleur/test/cloud-init-user-data-size.test.ts`. Measure the web gzip size before and after; if within about 30 B of the budget, raise `WEB_GZIP_BUDGET` in this PR (precedent: the #6425 / #8609 bumps) and add that test file to Files to Edit.
11. Render-diff proof (the only stand-in for the missing `plan_only` rehearsal; it adds, beyond `registry-render-delta.test.sh` and the dispatcher gate, a human-readable statement of exactly which bytes the host will receive): render the registry user_data at `origin/main` and at HEAD with `registry-userdata-budget.sh --json <out>`; the stripped renders differ only by the zot ref(s) / mirror values and the one deny line (comment edits render identically).

### Phase 5 — Docs

- ADR-096: one dated amendment line stating the registry deny names three hosts (mechanism unchanged). The 2026-10-08 `active` observation goes in the PR body, not in ADR-169 or the runbook (plan review: the toggle is not owned by this PR).
- Sidecar: complete the tables from Phase 2; the `## Why` section names v2.1.22 and keeps the floor at v2.1.19.

### Phase 6 — Ship (merge queue)

- Branch commit messages: end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. One commit message BODY (not its subject line) carries, each on its own line, `[skip-web-platform-apply]` and `[skip-deploy-fix-apply]` (decision D1). Evidence that this survives the queue's squash: this repo's squash message is `COMMIT_OR_PR_TITLE` + `COMMIT_MESSAGES`, and merged commits `fd1c4d5cac` (#9775) and `3ed3e4e6da` (#9348) show each branch commit rendered as `* <subject>` followed by its body lines unindented, which is what the kill-switch regex `(^|\n)\[skip-...\]($|\n)` needs. The skip is read only in each push workflow's `preflight` job, so the dispatched `registry-host-replace` (a `workflow_dispatch`) is unaffected. No commit carries an `[ack-destroy]` line; `git log origin/main..HEAD --format=%B | grep -c 'ack-destroy'` must print 0.
- PR 9795: remove the WIP title; body states `Ref #9252` and `Ref #9390` (no closing keyword), the delivery model, the rollback values, and ends with the Generated-with-Claude-Code line.
- Hard gate before `gh pr ready`: `zot_mirror_asset_sha256_amd64` differs from the v2.1.20 value `05b171f2...`, and `--check-asset` on the branch is CLEAR for the new asset. Misordering is otherwise caught only by P6 after the merge.
- The PR body records the 2026-10-08 observation that both apply workflows read `active`, and says that the deferred running-host delivery of copy B will land on the next push apply that includes those resources.
- The commit carrying the markers must survive: do not rebase it away or squash locally; after any rebase or amend, re-run the grep. The queue's squash text is the concatenation of the branch commit messages, so the local grep over `origin/main..HEAD` is the preventive check; AC14 is the detective one.
- Optional, only if credentials permit: a read-only `terraform plan -replace=hcloud_server.registry` with the six `-target`s and `-lock=false` (never an apply, plan file discarded), attached to the PR. The apply job's own plan-shape gate stays authoritative.
- Mark ready, enqueue with the normal merge path. Do not sync a queued PR. A branch that is BEHIND is enqueued anyway; wait.
- Before enqueue, run the full local preflight once more (read-only): `GH_TOKEN="$(gh auth token)" doppler run -p soleur -c prd_terraform -- bash scripts/registry-replace-preflight.sh` and attach the verdict line to the PR. It is an early reading; the dispatcher re-runs it.

### Phase 7 — Delivery and verification (post-merge; section below)

## Delivery Runbook (post-merge)

**Route.** The merge to `main` fires `registry-host-replace-dispatch.yml` on its `push` trigger (paths include `zot-registry.tf` and `cloud-init-registry.yml`). That is the sanctioned route and the only one used. The pipeline does not fire a second dispatch while it runs (double-replace hazard); `concurrency: registry-host-replace-dispatch` de-duplicates, and the apply workflow's `terraform-apply-web-platform-host` group serializes.

**What the run does, in order, and what each gate means.**

| Step | Meaning if it holds | If it is red |
|---|---|---|
| `gate`: render at the watermark vs head | The bytes that reach the host changed (expected: yes). `deliver=true` | `deliver=false` on this PR means the render did not change: stop and report (the diff is not what Phase 4 step 11 proved). `kind=gate-failed`: compare API unreadable, render unmeasurable or over 32,768 B: read its `::error::`, stop and report |
| preflight P0 | Better Stack query credentials readable; fails closed | Stop and report; do not retry blind |
| P1 | No sustained local-cache pulls in 24 h: the fleet is not already living off its last tier (#6400 hazard) | The fleet is already degraded. Stop and report. The manual arm's `--manual` skips only P1: never used without an explicit new go from the operator |
| P2 | Advisory only (emitter unreachable since #7071) | Never gates; ignore |
| P3 | No release run in flight (a release may be mid-pull from the host about to be destroyed); waits up to 2100 s | Times out: a release is stuck; stop and report |
| P5 | The replace will be observable: control + container-log channel both return rows | `--manual` does not skip it: a dark channel means the outcome cannot be read back. Stop and report |
| P6 | The boot asset named by the render exists and carries sha256 T | Phase 3 was skipped or T is wrong. Stop and report; fix by publishing, never by editing the preflight |
| dispatch | Fires `apply-web-platform-infra.yml --ref main -f apply_target=registry-host-replace -f reason=...` | `dispatch-failed`: an apply may still have queued; read the apply workflow's run list before anything else |
| apply job (`registry_host_replace`) | `environment: infra-privileged` (no reviewer; branch policy admits `main` only); P6 again; plan with `-replace=hcloud_server.registry` and 6 `-target`s (server, server network, volume attachment, firewall attachment, volume, and `doppler_secret.registry_betterstack_logs_token`); `registry_host_replace_gate` (exact scoped recreate, `hcloud_volume.registry` not deleted/forgotten, private NIC create present); `stock_preflight_gate` (Hetzner reports the server type orderable in the location); apply; post-apply jq assertions | Any abort: nothing destroyed if it is before apply. `class=stock` means wait for stock; `class=config|malformed|unreachable` have their own advice in the abort line. Stop and report; there is no `[ack-destroy]` bypass on this path and none is ever added |
| poll (1500 s) and verdict | The dispatcher records the apply's conclusion on the PR | `apply-failed`: the host may be dark and the volume is preserved. Read the apply step's `recovery-read` block first. Stop and report; a re-dispatch is a second destroy-first replace on the sole pull path and needs an explicit go |

**Inputs.** Push arm: none. Manual re-fire (only after the refusing predicate is resolved): `gh workflow run registry-host-replace-dispatch.yml -f reason='<why>' -f tracker=9795`. Direct route (documented for a registry dark over 24 h, not planned): `gh workflow run apply-web-platform-infra.yml -f apply_target=registry-host-replace -f reason='<why>'`. There is no `confirm`, no `web_host_key`, and `plan_only` is not honoured by this target.

**Rehearsal.** `plan_only` does not exist for this path, so the rehearsal is: Phase 4 step 11 (offline render diff), PR-time `zot-image-mirror` `rehearse` on three image stores against the real asset, and the local read-only preflight in Phase 6. The apply job's own plan-shape and stock gates are the last gate before apply.

**Red-gate protocol (any gate, any step).** Stop. Do not re-fire, do not add `--manual`, do not edit a gate or the preflight, do not add `[ack-destroy]`, do not run a plain `web-host-replace`, the web-2 volume rebirth, or any web-1 / git-data target, do not delete a `zot-image-*` release. Record the run URL, the verdict `kind` and the predicate, post them on PR 9795 and #9390 (non-destructive comments), and report. Read-only diagnosis is allowed. Next actions are the runbook's (`registry-host-replace-dispatch.md`), taken only on an explicit go.

**If a push apply runs anyway** (the kill-switch lines did not survive): read-only. Open the run, record its URL on PR 9795, confirm from its log which `terraform_data` resources it touched and that no `hcloud_*` resource changed. Do not cancel it mid-apply, do not re-fire it, report. The effect is not trivially bounded: `zot_consumer_probe_install` (web-1) and `deploy_pipeline_fix_web2` (web-2) re-run an idempotent hosts-file append with a post-deny resolution assertion, and `deploy_pipeline_fix` (web-1) redelivers `ci-deploy.sh` through the webhook (a comment-only change; its graceful web-1 swap is gated on a seccomp-profile verdict, which this change does not produce). `[skip-deploy-fix-apply]` is what keeps web-1 out of the second path. A failed hosts assertion taints only its `terraform_data` resource.

**Main-branch mirror run.** The merge also fires `zot-image-mirror.yml` on `main` (it watches `zot-registry.tf`); its publish job is idempotent here (release present, content-verified). A red `zot-image-mirror` run on the merge SHA is read as a P6 pre-signal, not ignored.

**Timebox.** The dispatcher's own ceilings are P3 2100 s and the apply poll 1500 s. If no `zot_image_fetch=ok` row newer than the apply's conclusion appears within 60 minutes of that conclusion (the host's fetch retries for up to about 35 minutes), treat it as red: stop and report on PR 9795 and #9390 with the latest row's `zot_image_fetch` value.

**Soak (numeric, read from the same telemetry).** Over the 24 hours after the replace: `zot_restarts=0`, no `zot_last_err` row at error or fatal level, the next release's `crane copy` to zot completes inside its window, and the `zot-fill-rate-7341` follow-through (which waited on zot#4235, fixed by #4236 in v2.1.21+) is read for a changed outcome. A failure of any of these is reported, not auto-reverted (see Rollback).

**Mid-replace failure (`apply-failed` after the destroy, volume preserved).** The host is down and deploys are frozen. The agent reports within the timebox with the `recovery-read` block's `class=` and the exact one-step recovery (re-dispatch of the same route); whether that single re-dispatch may be pre-authorised is an open operator decision (D4 in decision-challenges.md). Until it is, the re-dispatch waits for an explicit go.

**Verify the new host from telemetry (no SSH).**

```bash
doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 2h --grep SOLEUR_ZOT_DISK --limit 5
```

Healthy means a row newer than the apply's conclusion with `zot_image_fetch=ok`, `zot_image_digest=46f688dc2631` (D12 of the pinned manifest; re-derive from the final pin), `ghcr_blocked=1`, `state_status=running`, `zot_restarts=0`, `store_luks=yes`. `docker.pkg.github.com` has no per-name field, and `ghcr_blocked` probes `ghcr.io` only, so it reads identically on the old and new render. What it proves is that the deny entry ran and ghcr.io is sinkholed; `zot_image_digest=<final D12>` proves the NEW render booted. The proof that the third name is denied on the registry host is R10 (the rendered entry executed against a re-rooted hosts file) plus the Phase 4 step 11 render diff. #9390 is closed on those, with the limit stated in the closing comment. Also read the `soleur-registry-disk-prd` heartbeat status (best effort). Any other `zot_image_fetch` value: use the table in the runbook's "zot boot image" section, and stop and report.

**Close-out.** Comment the evidence on #9390 and close it. #9252 stays open until PR 9783 lands (then the next rule-audit poll sees both pins current). File one tracking issue for the deferred running-host delivery of copy B (decision D1), owner the operator, target date 2026-10-22 to decide between a deliberate `workflow_dispatch` of the owning apply workflow and incidental delivery by a later infra merge (an incidental delivery that fails its post-deny assertion taints and fails an unrelated PR's apply), with re-evaluation criteria "the next push apply (or manual apply) that includes `zot_consumer_probe_install` or `deploy_pipeline_fix_web2`, which will deliver it unannounced; close when state carries the new hash", milestone from `knowledge-base/product/roadmap.md`, `Ref #9390`. The issue body also says that the 12-hourly `scheduled-terraform-drift` run will report `triggers_replace` drift for `zot_consumer_probe_install` and `deploy_pipeline_fix_web2` until then, so a drift report is expected, not a regression.

## Failure Branches (non-gate)

| Situation | Branch |
|---|---|
| `zot-image-mirror` dispatch: `publish` job red | A re-dispatch is safe (it deletes leftover drafts and verifies an existing release by content). Never delete a release. If it stays red, stop and report with the failing step. |
| Dispatch: published sha256 differs from the run's rebuild | STOP before pinning (see Phase 3). |
| Dispatch: its `rehearse` jobs red | Read the failing step: `sha_mismatch` / manifest mismatch against the not-yet-updated T and C is the expected pre-commit-B state; any other `zot_image_fetch` value (`load_failed`, `id_mismatch`, `docker_unavailable`) is a real boot failure on the new asset: stop and report. |
| Merge queue ejects the PR (red `merge_group` check, or `main` moved) | Read the failing check, fix on the branch, re-run the Phase 6 preflight, the `ack-destroy` and kill-switch greps, and the Phase 4 step 11 render diff against the current `origin/main`; re-confirm AC6; then re-enqueue. Never sync a queued PR. |
| PR 9783 (ubuntu half) merges first or later | No file or workflow conflict. Phase 0 reads its body for a closing keyword on #9252 (comment and reopen if it closed the issue early); the render diff is re-run against the current `origin/main` immediately before `gh pr ready`. |
| Another infra PR is open-ready or queued | Do not enqueue anything touching `apps/web-platform/infra` or release paths until AC13 is green: a later infra merge runs a full-scope apply that would deliver copy B to web-1 and web-2 unannounced. Before enqueue, confirm both marker lines with `gh pr view 9795 --json commits`. |
| Dispatcher run never appears for the merge SHA | Read the SHA with `gh pr view 9795 --json mergeCommit`, arm a watch on the `registry-host-replace-dispatch.yml` run for that SHA (a registration lag of up to 30 minutes is documented in the workflow). No run within 10 minutes: stop and report; no manual dispatch. |
| `deliver=false` on the merge SHA | The pin is merged and the host is not replaced. Read `watermark=` and the render-compare lines from the run log, post them on PR 9795, and stop. The recovery is the dispatcher's manual arm (which delivers unconditionally), taken only on an explicit go. Terminal state for the autonomous run: report, emit the resume prompt, end. |
| Waiting for an explicit go | Only read-only telemetry reads and comments on PR 9795 / #9390; no re-fire, no dispatch. |

## Rollback

The superseded pin's asset is immutable and published, so P6 passes for it. Revert the four values (`zot_image_amd64`, `zot_image_arm64`, T, C) from the sidecar's previous-known-good block, plus the deny list if wanted, in one revert PR; the dispatcher sees the render change and replaces the host back. The revert commit carries the same two own-line kill-switch markers (it touches `server.tf` and `ci-deploy.sh` again, so it would otherwise fire both push applies). Decision rule: roll back only when `zot_image_fetch` is `id_mismatch` or `load_failed` after one re-fire, or the soak fails. Both the re-fire and the rollback are explicit-go-only steps (they are the red-gate protocol's exception, taken on the operator's go, never on the agent's own initiative). A revert is a second destroy-first replace and is subject to the same gates (including stock). If the push-arm run is refused on P1 because deploys fell to local-cache during an outage, the documented route is the manual arm, which needs an explicit go.

## Downtime & Cutover

**Operation and surface.** `registry-host-replace` destroys and recreates `hcloud_server.registry`, the host that serves the fleet's sole pull path. While it is down: running web and inngest containers keep serving (they do not pull at runtime), deploys fail at the pull step and wait, and a fresh web-host boot fails at its pull stage. The zot store volume is preserved and reattached, so no image is re-uploaded.

**Zero-downtime path evaluated, and why it is not available.** Blue-green (a second registry host live before the cutover) is not possible here: the store is one LUKS volume attached to one host at a time, ADR-096 and ADR-169 decide a single registry host with no tier beneath it (the host-to-GHCR fallback was retracted in #7071), and the host is cloud-init-only, so an in-place change does not exist (`user_data` is ForceNew). Drain-then-act IS available and is built in: P3 refuses to start while a release run is in flight, P1 refuses when the fleet is already on its last tier, and the stock gate refuses before the destroy when Hetzner reports the server type unorderable.

**Bounded window and sign-off.** The window is the apply job plus the host's boot and bounded asset fetch (the fetch retries up to about 35 minutes; the 60-minute timebox in the Delivery Runbook is the stop line). The dispatcher's push runs of 2026-09-28 and 2026-09-30 concluded success through the same route. The operator approved this replace on 2026-10-08 (brief: "The operator has explicitly approved BOTH the code change and the production registry-host replace apply (2026-10-08)").

**Per-stage verification and rollback.** Verification: preflight CLEAR before; plan-shape and stock gates before apply; post-apply store-volume-preserved and NIC-create assertions; telemetry row after. Rollback: Rollback section (revert the four values; the previous asset is published and immutable).

## Infrastructure (IaC)

### Terraform changes
No new resource. Edits to existing locals in `zot-registry.tf` and `server.tf`; no provider or version change; no new variable or secret.

### Apply path
(b) `terraform apply -replace` of `hcloud_server.registry` through the existing dispatcher and `registry_host_replace` job: destroy-first, store volume preserved, expected outage window of the registry only (tens of minutes; running containers keep serving, deploys wait). Not a user-run step: the pipeline performs it on merge.

### Distinctness / drift safeguards
Registry-only `-target` set; `hcloud_server.web` keeps `ignore_changes=[user_data]`, so copy A reaches fresh web hosts only. Copy B edits `triggers_replace` of two `terraform_data` SSH resources (web-1, web-2): see D1.

### Vendor-tier reality check
Hetzner stock for the registry server type in its location is the one live uncertainty; `stock_preflight_gate` reads Hetzner's `locations[].available`. A `class=stock` abort happens before the destroy.

## Observability

The registry host is outside layers 1 to 5 (no Inngest, no Sentry-shipping Vector on that host); its signals are the Better Stack heartbeat and log rows, plus the synchronous workflow run log of the dispatcher and apply jobs. Layer names below are the reviewer's substrings.

```yaml
liveness_signal:
  what: "SOLEUR_ZOT_DISK heartbeat rows (zot_image_fetch, zot_image_digest, ghcr_blocked, state_status, zot_restarts, store_luks) and the soleur-registry-disk-prd Better Stack heartbeat (Sentry monitor class: absence is the page)"
  cadence: "every 5 minutes"
  alert_target: "Better Stack heartbeat incident; registry-host-replace-dispatch verdict comment on the delivering PR"
  configured_in: "apps/web-platform/infra/cloud-init-registry.yml (emitter, one SOLEUR_ZOT_DISK line assembly) and apps/web-platform/infra/zot-registry.tf (heartbeat resource)"

error_reporting:
  destination: "workflow run log of registry-host-replace-dispatch.yml and apply-web-platform-infra.yml (::error:: annotations) plus a verdict comment on the PR; Better Stack log source 2457081 for host-side rows"
  fail_loud: "preflight ::error:: with verdict=REFUSED predicate=Pn; stock-preflight ABORT with class=; apply-failed verdict kind with the recovery-read block; zot_image_fetch other than ok in the heartbeat row"

failure_modes:
  - mode: "boot asset missing or wrong sha256 (P6)"
    detection: "workflow run log: preflight P6 ::error:: before any destroy; after a boot, zot_image_fetch=sha_mismatch or download_failed in the SOLEUR_ZOT_DISK row"
    alert_route: "dispatcher verdict comment (refused) and the heartbeat Sentry monitor-class absence"
  - mode: "Hetzner stock short for the registry server type"
    detection: "workflow run log: stock-preflight ABORT ::error:: with class=stock before the destroy; if the create fails after the destroy, the apply step's ::error:: plus the stock_recovery_report recovery-read block"
    alert_route: "apply run failure, dispatcher verdict kind apply-failed, and the heartbeat absence"
  - mode: "dispatcher refuses or fails to dispatch (kinds refused, dispatch-failed, gate-failed, cancelled, unverified)"
    detection: "workflow run log of the dispatcher job; the verdict comment carries a machine marker readable with the runbook's jq"
    alert_route: "verdict comment on PR 9795 (or the owner issue)"
  - mode: "new host boots but zot does not start (id_mismatch, load_failed, docker_unavailable)"
    detection: "zot_image_fetch value in the SOLEUR_ZOT_DISK row, read by betterstack-query.sh; no Better Stack log alert exists on zot_image_fetch not being ok, so the detectors are the heartbeat absence (Sentry monitor class) and the 60-minute timebox in the runbook"
    alert_route: "Better Stack heartbeat incident, then the agent's stop-and-report"
  - mode: "new host healthy but its log shipper is silent (no rows), indistinguishable from a slow boot fetch of up to about 35 minutes"
    detection: "no SOLEUR_ZOT_DISK row newer than the apply conclusion after 60 minutes (the timebox) while the heartbeat is up"
    alert_route: "agent stop-and-report on PR 9795 and #9390"
  - mode: "hosts-file deny lost on the registry host (ghcr.io only is probed)"
    detection: "ghcr_blocked=0 in the heartbeat row; the Better Stack log alert on ghcr_blocked=0 (betterstack-logs-alerts.tf) fires; unknown is not alerted and is read by the agent"
    alert_route: "Better Stack alert"
  - mode: "kill-switch lines dropped by the squash, so the push applies reach web-1 and web-2 over SSH"
    detection: "workflow run log: the preflight job of apply-web-platform-infra.yml and apply-deploy-pipeline-fix.yml shows skip=false for the merge SHA (AC14)"
    alert_route: "agent stop-and-report with the run URL"

logs:
  where: "Better Stack source 2457081 (SOLEUR_ZOT_DISK rows, container logs); GitHub Actions run logs for the dispatcher and apply jobs"
  retention: "Better Stack retention for the source; GitHub Actions log retention for run logs"

discoverability_test:
  command: bash scripts/betterstack-query.sh --since 2h --grep SOLEUR_ZOT_DISK --limit 5
  expected_output: zot_image_digest=46f688dc2631
  credentials_required: "Doppler soleur/prd_terraform Better Stack ClickHouse read credentials (run the command under doppler run -p soleur -c prd_terraform --): Better Stack log rows have no unauthenticated read path, so no unauthenticated probe verifies the same property"
```

The `soleur-registry-disk-prd` heartbeat goes absent by design while the host is replaced, so an incident opens during the window and auto-resolves; the new host's rows, not the incident's resolution, are the proof. The `expected_output` literal is the D12 of the pre-reading digest and is re-derived from the final pin.

## Encryption Posture` sections the deepen gates require; cut Guard 2 and the ADR-169 / runbook edits (simplification panel); added timebox, push-apply-fires-anyway protocol, numeric soak, rollback decision rule.

### New considerations discovered
- `ghcr_blocked` probes ghcr.io only; the third name is proven by R10 and the render diff, not by telemetry.
- The 12-hourly drift run will report `triggers_replace` drift for web-1/web-2 after the kill-switched merge.

## Overview

Two open issues each change a render input of the registry host's `user_data`, so they ship as one
change and one delivery. Issue 9252 moves the zot image pin in `zot-registry.tf` (the ubuntu half of
that issue is a different PR and is not in this one). Issue 9390 adds a third name to the hosts-file
deny that the registry runcmd entry writes. Both force the registry host through a destroy-first
`registry-host-replace`; bundling them means the sole pull path goes through one outage window, not two.

The delivery is the existing `registry-host-replace-dispatch.yml` push arm, which fires on merge. This
plan adds no workflow, no new gate and no new probe. The work is: a pin bump that follows the sidecar's
Bump procedure, a deny edit at every byte-identical site, and a delivery runbook that says what each
gate means and what to do when one is red.

Live state at plan time (2026-10-08, read, not assumed):

- upstream zot latest is `v2.1.22` (published 2026-10-06T16:50Z); pinned is `v2.1.20`.
- `apply-web-platform-infra.yml` and `apply-deploy-pipeline-fix.yml` both read `active` (updated
  2026-10-08T19:07Z); the registry dispatcher reads `active`. The earlier "paused" prose in ADR-169's
  2026-10-03 amendment and `cron-egress-blocked.md` is superseded by today's state. A merge therefore
  fires BOTH push applies (they reach web-1 and web-2 over SSH) AND the registry dispatcher.
- `scripts/registry-replace-preflight.sh` run read-only against production reads
  `verdict=CLEAR local_cache_hits=0 ghcr_fallback_hits=0 in_progress_releases=0 obs_control_hits=200
  obs_channel_hits=200` for the current pin's asset.
- PR 9783 (the ubuntu:24.04 base-pin half of #9252) is still OPEN, not merged.

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality (checked) | Plan response |
|---|---|---|
| "the ubuntu:24.04 half is already shipped by a separate PR" | PR 9783 `chore(infra): bump the ubuntu:24.04 base pin in the git-data rehearsal` is OPEN | PR body uses `Ref #9252`, never a closing keyword. No ubuntu edit here. |
| Apply workflows paused (ADR-169 amendment 2026-10-03, runbook prose) | Both `active` since 2026-10-08T19:07Z; apply runs succeeded today | Merge-time web-host contact is real. Decision D1 below (kill-switch lines) reconciles it with "do not touch web-1". |
| "rehearsing with plan_only first where the path supports it" | `plan_only` is declared for `web-host-replace` and `git-data-host-replace` only; the `registry_host_replace` job has no `plan_only` conjunct | No `plan_only` rehearsal exists for this path. Substitutes: offline render diff, PR-time `rehearse` x3 stores, local read-only preflight. Not adding `plan_only` (would edit a workflow: no admin-merge path, byte budget). |
| #9390 lists six byte-identical sites | A seventh carries the deny literals: `cloud-init-ghcr-seed-login.test.sh` (`DENY_HEADER`, `DENY_BLOCK`, `DENY_HDR`, mutation rows 16c/17/18) | Added to Files to Edit (inferred, justified in Scope Check). |
| Step 3 "re-diff the four upstream anchors" is the compatibility analysis | v2.1.20 to v2.1.22 is 128 commits, one breaking (`fix(api)!` #4363, in v2.1.21). Measured against this repo's exact config: HEAD of a blob that exists only under another repo is 200 on v2.1.20 and 404 on v2.1.22; `POST ?mount=` unchanged. Also the distSpec WARN now fires (config 1.1.0, supported 1.1.1) | Added step 3b (breaking-change scan) to this bump and to the sidecar's Bump procedure. |
| Previous known-good pin format | Staleness check 8 parses `zot-linux-<arch>@sha256:<64hex>` (tag-less) in `## Previous known-good pin` | Rotate in that exact shape; also record v2.1.20's T, C and release tag so rollback needs no git archaeology. |
| Step 5 "publish the boot asset via zot-image-mirror.yml BEFORE the bump merges" | The builder reads D from the checked-out `zot-registry.tf`; a branch dispatch builds whatever the branch pins | Commit the new `zot_image_*` locals and push BEFORE dispatching; pin T and C in a second commit. |
| "a PR touching .github/workflows has no agent admin-merge path" | The planned diff touches no `.github/workflows/*` file | Stated as an AC; ordinary merge-queue path. |

## Research Insights

**Premise validation (Phase 0.6).** Held: #9252 and #9390 OPEN; draft PR 9795 OPEN; the dispatcher, preflight
script, ADR-169 amendments and the runbook exist on `origin/main` (`d0b5d2e35b`). Stale: "ubuntu half
shipped" (PR 9783 open); "paused" apply workflows (active); "plan_only where supported" (unsupported on
this path); #9390's six-site list (seven). The mechanism was checked against the ADR corpus: ADR-096
(amendment 2026-09-28 part 2) and ADR-169/190 already decide the boot-asset design and the replace
authorization, so no decision here is new.

**Property List (Phase 0.6b).**
1. After the replace, the registry host runs zot at the current upstream pin, booted from a published, digest-verified asset.
2. The host-process hosts-file deny covers docker.pkg.github.com, and every byte-identical copy still equals the registry's entry.
3. Nothing is bypassed and no host other than the registry is replaced (store volume preserved).
4. The new host is shown healthy from telemetry, with no SSH.
5. The rollback target for the superseded pin survives the bump.

**Cut List.**
- `plan_only` for the registry job: P3 is already covered by the dispatcher gate, preflight, and the apply job's own plan-shape and stock gates.
- A new follow-through probe: P4 is covered by `SOLEUR_ZOT_DISK` rows read with `scripts/betterstack-query.sh`.
- A per-name `ghcr_blocked` probe for docker.pkg.github.com: no property needs it; R10 executes the rendered entry and `ghcr_blocked=1` proves the same loop ran.
- A second, manual dispatch of the replace: the merge-fired dispatcher is the route; a second one is the double-replace hazard.
- Adopting `hydrateBlobOnRead`, `distSpecVersion` 1.1.1, `FastRestart`, `keepUntagged`: config JSON stays byte-unchanged unless step 3b hits its STOP rule.
- A new ADR: no new decision; dated amendment lines only.

**Measured at plan time (re-measure at work time; these are pre-readings, not the record).**
- Digests (anonymous ghcr.io token, same method reproduces the v2.1.20 pins): amd64 v2.1.22 `sha256:46f688dc26315a35a247e1784368829e66a67bf91de94c7d8d1645044fac1d5b`, arm64 v2.1.22 `sha256:920e3e327a73513643c67d14f54092c45ece6d29660bff7e898107e00b49fa03`. amd64 manifest `.config.digest` (C): v2.1.20 `2d7fee56...` (matches the pin), v2.1.22 `sha256:5a8db63c9fae93403c39376052e205c41a469dbd84b3d1ea37ee497cb08318ef`. D12 for telemetry: `46f688dc2631`.
- Four anchors v2.1.20 vs v2.1.22 (source at the tags): `func updateDistSpecVersion` IDENTICAL; `type RetentionPolicy` IDENTICAL; `type KeepTagsPolicy` IDENTICAL; `type AccessControlConfig` IDENTICAL; `GlobalStorageConfig` and `HTTPConfig` IDENTICAL; `pkg/compat/compat.go` `DockerManifestV2SchemaV2 = "docker2s2"` unchanged, two additive helpers (`IsImageManifestMediaType`, `IsImageIndexMediaType`).
- Claim 1 (200 or 401, never 403), exact `config.json` from `cloud-init-registry.yml` with synthetic users and bcrypt htpasswd, both pinned digests, local docker: anon `/v2/` 401, pull user 200, push user 200, bad password 401, missing repo 404; zero 403. Claim 2 (no on-demand gc endpoint): `/v2/_zot/gc`, `/v2/_catalog/gc`, `/_zot/gc`, `/v2/_zot/ext/gc` all 404 on both. v2.1.22 emits `level":"warn"` for `config dist-spec version differs` (1.1.0 vs 1.1.1) and zero error/fatal lines, so the `zot_last_err` error/fatal tiers are not tripped.
- #4363 effect: HEAD `repob/blobs/<digest>` for a blob uploaded only to `repoa`: v2.1.20 200, v2.1.22 404; `POST repob/blobs/uploads/?mount=<digest>&from=repoa` 201 on both and HEAD then 200. `storage.dedupe` is `true` in the deployed config, so this applies. CI pushes with `crane copy` GHCR to zot (cross-registry: no mount path), so a layer shared by two zot repos is uploaded again instead of skipped. Slower, not broken; bounded by the 1800 s deadlines ADR-190 sized.
- Full preflight against production, read-only, from this worktree (see overview): CLEAR.
- Budget: `registry-userdata-budget.sh --json` stored 20,932 B, cap 32,768, headroom 11,836 B. Three names add tens of bytes.

**Other v2.1.21/22 commits read against this config** (full list: `gh api repos/project-zot/zot/compare/v2.1.20...v2.1.22`):
#4318/#4236/#4351/#4325/#4383 (gc/dedupe/walk changes: covered by the soak after the replace, not by a unit measurement); #4447 (digests stay pullable after last-tag overwrite: retention semantics, additive); #4419 (skip `lost+found` in storage walks: the ext4 store root carries one); #4285 (htpasswd hot-reload: the measured 200/401 matrix covers file-mounted htpasswd); #4380 (dedupe mount auth enforced); #4414 (HSTS on TLS responses: the host serves plain HTTP behind the tunnel, n/a); #4307 (sigstore v3 bundle recognition: cosign path, additive).

**Institutional learnings applied.** `2026-09-30-my-deny-guards-proved-one-template-arm-and-missed-one-line-blocks` (parity must be rendered on BOTH `web_tunnel_connector` arms); `test-failures/2026-10-06-which-files-feed-user-data-...` (`hcloud_server.registry` has no `ignore_changes=[user_data]`; sibling suites pin edited lines by text: `web-ghcr-deny.test.sh`, `cloud-init-user-data-size.test.ts`, `ci-deploy.test.sh`); `2026-07-26-cloud-init-comment-is-a-live-host-input-...` (a comment is only inert because the render strips it: assert the render diff, do not assume); `2026-06-02-auto-merge-livelock-fast-moving-main` §merge queue (never sync a queued PR); vector-redeliver runbook (a kill-switch line counts only in a branch COMMIT message, never the PR body).

## User-Brand Impact

- **If this lands broken, the user experiences:** a registry host that boots dark: running web containers keep serving, but every deploy (including security fixes) fails at the pull step until the host is restored, and a fresh web-host boot fails at its pull stage.
- **If this leaks, the user's data is exposed via:** no data path changes. The change moves a public image pin and adds a blocked hostname; no credential, no user data and no store content is touched (the zot store volume is preserved).
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** not `single-user incident` because no user data or per-user workflow is exposed; not `none` because a failed destroy-first replace under a Hetzner stock shortage can freeze deploys fleet-wide for hours (#6393 precedent), which is an aggregate availability pattern.

## Hypotheses

This plan diagnoses no connectivity symptom, so the L3-to-L7 layers have nothing to verify; each is recorded so the gate's intent is visible. The keyword that triggered the gate is "no SSH": it names an exclusion, plus the SSH `remote-exec` provisioners that consume copy B (below).

- L3 firewall allow-list: not applicable. No new network path is opened; the deny closes a name. The Hetzner firewall carries inbound rules only and is not edited.
- L3 DNS and routing: not applicable to an outage; the deny is a name-resolution sinkhole by design. The one resolution fact that matters is asserted by copy B's own post-deny `getent ahosts` check on the web routes.
- L7 TLS and proxy: not applicable. The registry is reached over the private network and the Cloudflare tunnel; neither is edited.
- Service layer: the SSH provisioners that consume `local.ghcr_deny_sh` (`zot_consumer_probe_install` on web-1, `deploy_pipeline_fix_web2` on web-2) are the only SSH dependency this change creates. Decision D1 keeps the merge from firing them.

## Open Code-Review Overlap

One open scope-out names a planned file path: #2197 (billing `SubscriptionStatus` type refactor), whose body mentions `apps/web-platform/infra/server.tf` incidentally. Acknowledge: unrelated concern (billing types), stays open.

## Files to Edit

Infra (`apps/web-platform/infra/`):
- `zot-registry.tf`: `zot_image_amd64`, `zot_image_arm64` (v2.1.22 + both digests); `zot_mirror_asset_sha256_amd64` (T); `zot_config_digest_amd64` (C).
- `zot-image.provenance.md`: header table, `## Current pin`, `## Previous known-good pin` (rotated, tag-less, plus v2.1.20 T/C/release tag), `## Why v2.1.22` (floor stays v2.1.19), config-compatibility table (re-diffed), non-adoption list, version-scoped claim register (dates), new Bump-procedure step 3b, capture date.
- `cloud-init-registry.yml`: copy R (third name); comment claims that name `zot v2.1.20` (three places) re-measured and re-dated.
- `cloud-init.yml`: copy A.
- `server.tf`: `local.ghcr_deny_sh` and `local.ghcr_deny_assert_sh` (copy B).
- `ci-deploy.sh`: comment-only: the `zot v2.1.20 ... MEASURED 2026-08-05` claim block above `_docker_login_failure_class`.
- `ci-deploy.test.sh`: the "401 fixture is byte-accurate - reproduced against the pinned zot v2.1.20" comment (staleness check 7 follower; re-measure the 401 fixture against the final digest before re-dating it).
- `scripts/followthroughs/zot-fill-rate-7341.sh`: header and FAIL message say "zot#4235 is unfixed in v2.1.20"; upstream #4235 is CLOSED and its fix PR #4236 merged 2026-08-11 (in v2.1.21+), so after the replace the sentence is false. Reword to the measured state; no logic change.
- `web-ghcr-deny.test.sh`: `HDR`, getent shim (third name), exec/agree/census rows, mutation rows.
- `zot-image-fetch.test.sh`: R5 header literal, R10 counts (hosts file 5 lines becomes 7; per-name counts), the `v2.1.20` fixture string.
- `cloud-init-ghcr-seed-login.test.sh`: `DENY_HEADER`, `DENY_BLOCK`, `DENY_HDR`, mutation rows that embed the header.
- `zot-image-staleness.test.sh`: only if a count or comment names the version (read first; the floor `MIN_ASSERTIONS` is not lowered).

Docs:
- `knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md`: dated amendment line (deny now names three hosts).
- Not edited (plan review cut them): ADR-169's 2026-10-03 amendment and `cron-egress-blocked.md` carry stale "paused" prose, but the toggle is not owned by this PR; the PR body records the 2026-10-08 `active` observation instead.

## Files to Create

None in product code. The pipeline artifacts `knowledge-base/project/specs/feat-one-shot-9252-zot-pin-bump-ghcr-deny/tasks.md` and `decision-challenges.md` are created by the plan phase and already committed.

Not touched, by instruction: `.github/workflows/*`, `.mcp.json` (pre-existing local modification: stage explicit paths only), `git-data-runcmd-rehearsal.test.sh` (ubuntu half), anything for web-1, web-2, git-data.

## Implementation Phases

TDD order inside each phase: tests that name the new value go RED first (`cq-write-failing-tests-before`), then the edit.

### Phase 0 — Preconditions (read-only)

- Confirm `git branch --show-current` is the feature branch; `git fetch origin main`; no tracked modifications other than possibly a stray `.mcp.json` (never stage it).
- Re-read: `gh api repos/jikig-ai/soleur/actions/workflows/<file> --jq .state` for the three workflows; `gh release list -R project-zot/zot --limit 3` (latest may have moved past v2.1.22: if so, redo steps 2 to 6 for the new tag and say so in the PR); `gh pr view 9783 --json state`.
- Baseline: the suites for the files being edited (AC1, AC7) are green on the untouched tree.

### Phase 1 — Rotate the previous-known-good pin, then resolve both digests (prerequisites 1, 2)

1. In `zot-image.provenance.md` `## Previous known-good pin`, replace both rows with the v2.1.20 refs in the tag-less shape the staleness check parses: `ghcr.io/project-zot/zot-linux-amd64@sha256:95a837a0...fd5 (v2.1.20)` and `...arm64@sha256:56230c5a...ff6 (v2.1.20)`, superseded 2026-10-08. Add a line with the v2.1.20 boot-asset facts: release `zot-image-v2.1.20-95a837a0afac`, T `05b171f2bd500dc84f532ef7736d1550ffaf7464f0d655c86b8238b443568cb2`, C `2d7fee5603dfd88b2b90cffd07e6b97e6d7ba5e3d6bd5472e66b23bd5ad59114` (that release is immutable and published; P6 reads CLEAR for it today).
2. Resolve with `crane digest` (or the anonymous-token curl used at plan time, which reproduced the v2.1.20 pins) for BOTH `zot-linux-amd64` and `zot-linux-arm64` at the target tag. Never one arch. The two digests must differ.
3. Edit `zot_image_amd64`, `zot_image_arm64` in `zot-registry.tf` and `## Current pin` together. Commit A (pin locals + rotation). Push the branch.

### Phase 2 — Anchors, claims, breaking-change scan (prerequisites 3, 4)

3. Re-diff the four anchors v2.1.20 to the target tag from upstream source (not release notes). Update the config-compatibility table with a verdict per anchor. Pre-reading: all identical, `compat.go` additive.
3b. Breaking-change scan: list commits between the tags whose subject carries `!:` or `BREAKING`; for each, read the PR body and decide whether it touches a surface this config uses. #4363 does (`dedupe: true`). Re-run the plan-time measurement (two repos, upload to one, HEAD/mount against the other, on both pinned digests) and record the result in the config-compatibility table. Add one line to the sidecar's Bump procedure ("scan `!:`/BREAKING commits between the tags") and nothing more. Shared-layer question, one question only: does any layer that two zot repos would share exceed what the `crane copy` retry/deadline window in `reusable-release.yml` can re-upload (ADR-190 sized the server deadline at 1800 s)? STOP rule, limited to what is testable before merge: if that answer is yes, or the same-repo HEAD, push or pull matrix differs between the two versions, stop, record it, and do not mark ready; the fix would be `storage.hydrateBlobOnRead: true` (a config JSON change: `registry-boot-guard.test.sh` fragments and a fresh decision), not part of this plan. gc/retention behaviour is covered by the post-replace soak (see Delivery Runbook), not by this rule. Otherwise `hydrateBlobOnRead` is recorded NOT ADOPTED, with the measured reason, in the sidecar only.
4. Re-measure the two version-scoped claims by running the pinned image locally with this repo's exact `config.json` (extract the `/etc/zot/config.json` block from `cloud-init-registry.yml`, substitute synthetic users for `${zot_pull_user}` / `${zot_push_user}`, bcrypt htpasswd) and probing `/v2/` for 200-or-401 and the four gc paths for 404. If any 403 appears: STOP, downgrade the claim to `UNMEASURED`, file an issue, do not ship the comment. Update the three `zot vX.Y.Z` comment sites in `cloud-init-registry.yml`, the block in `ci-deploy.sh` and the comment in `ci-deploy.test.sh` to the target tag and the new measurement date (staleness check 7 reads all three followers). Unregistered version-scoped claims, listed in the sidecar's claim register so the next bump finds them: `.github/workflows/reusable-release.yml` ("zot v2.1.20's built-in ReadTimeout/WriteTimeout", a default that the explicit 1800 s config overrides; the file is a workflow and is left alone) and `scripts/followthroughs/zot-fill-rate-7341.sh` (reworded here). Confirm the scraper still matches the v2.1.22 log shape (`"level":"error"` form) and note the new distSpec WARN is warn-level.
6. Re-stamp `Capture date (UTC)` only after steps 2 to 4 are done; run `zot-image-staleness.test.sh` (must exit 0) and `zot-image-staleness-mutation.test.sh`.

### Phase 3 — Publish the boot asset BEFORE the bump merges (prerequisites 5, 6)

Ordering constraint (between a workflow dispatch and a PR merge, spelled out):

```text
commit A (new zot_image_* locals) pushed to the branch
  -> gh workflow run zot-image-mirror.yml --ref feat-one-shot-9252-zot-pin-bump-ghcr-deny
  -> publish job: builds from upstream D (the branch's pin), creates release zot-image-<ver>-<D12>
     as a DRAFT prerelease, uploads the asset, publishes it (immutable from here); prints PUBLISHED_T
  -> rehearse job (3 stores) boots the published asset
  -> pin T = PUBLISHED_T and C = manifest .config.digest in the zot-mirror block; commit B; push
  -> PR CI rehearse rebuilds from upstream D and must reproduce T and C
  -> ONLY THEN may the PR be marked ready / enqueued
```

Why it cannot be later: after the merge, the dispatcher's preflight P6 (and the apply job's own P6) refuses a replace whose asset is unpublished, so a merge-first order produces a `refused` verdict and an unreplaced host that nothing re-fires by itself. Why it cannot be earlier than commit A: the builder reads D from the checked-out `zot-registry.tf`.

- The publish is irreversible and harmless if the PR is abandoned: `zot-image-*` releases are never deleted and are not "latest".
- Read T from the run summary (`published T`) via `gh run view <id> --log | grep PUBLISHED_T`; if the workflow warns that the published sha256 differs from its own rebuild, pin the PUBLISHED value.
- Verify with `GH_TOKEN="$(gh auth token)" bash scripts/registry-replace-preflight.sh --check-asset` on the branch: must print `verdict=CLEAR predicate=P6` naming the new asset.
- Only the `publish` job of the dispatch matters at this point; its own `rehearse` job runs against T and C values that are still v2.1.20's, so it is expected RED, as are the PR's `rehearse` jobs and staleness check 7 (claims still naming v2.1.20) between commit A and the final commit. That is the ordering, not a defect.

### Phase 4 — The hosts-file deny at every site (prerequisite 7)

Target shape: the loop header becomes `for h in ghcr.io pkg-containers.githubusercontent.com docker.pkg.github.com; do`, appended last so the existing leading literal stays a prefix. Everything else in the entry is byte-unchanged.

7. Tests first (RED): `web-ghcr-deny.test.sh` (`HDR`, getent shim case for the third name, exec expectation of 3 names x 2 lines, agree rows, census), `zot-image-fetch.test.sh` (R5 literal; R10: hosts file `localhost` + 6 lines = 7, per-name once each, template line count), `cloud-init-ghcr-seed-login.test.sh` (`DENY_HEADER`, `DENY_BLOCK`, `DENY_HDR` and the rows that splice the header).
8. Edit copy R (`cloud-init-registry.yml` runcmd entry), copy A (`cloud-init.yml` runcmd[1]), copy B (`server.tf` `ghcr_deny_sh` loop and `ghcr_deny_assert_sh` loop). All three loops get the same three names in the same order. Run `web-ghcr-deny.test.sh` on both `web_tunnel_connector` arms (the suite does).
9. Sweep for any other literal: `git grep -n "for h in ghcr.io"` and `git grep -n "pkg-containers.githubusercontent.com" -- ':!knowledge-base/project'` and disposition every hit (the `cron-egress-*` and Sentry hits are the separate #9275 bridge layer: not touched).
10. Size and render gates: the AC8 suite list (headroom stays above 10 kB; baseline 11,836 B).
11. Render-diff proof (the only stand-in for the missing `plan_only` rehearsal; it adds, beyond `registry-render-delta.test.sh` and the dispatcher gate, a human-readable statement of exactly which bytes the host will receive): render the registry user_data at `origin/main` and at HEAD with `registry-userdata-budget.sh --json <out>`; the stripped renders differ only by the zot ref(s) / mirror values and the one deny line (comment edits render identically).

### Phase 5 — Docs

- ADR-096: one dated amendment line stating the registry deny names three hosts (mechanism unchanged). The 2026-10-08 `active` observation goes in the PR body, not in ADR-169 or the runbook (plan review: the toggle is not owned by this PR).
- Sidecar: complete the tables from Phase 2; the `## Why` section names v2.1.22 and keeps the floor at v2.1.19.

### Phase 6 — Ship (merge queue)

- Branch commit messages: end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. One commit message BODY (not its subject line) carries, each on its own line, `[skip-web-platform-apply]` and `[skip-deploy-fix-apply]` (decision D1). Evidence that this survives the queue's squash: this repo's squash message is `COMMIT_OR_PR_TITLE` + `COMMIT_MESSAGES`, and merged commits `fd1c4d5cac` (#9775) and `3ed3e4e6da` (#9348) show each branch commit rendered as `* <subject>` followed by its body lines unindented, which is what the kill-switch regex `(^|\n)\[skip-...\]($|\n)` needs. The skip is read only in each push workflow's `preflight` job, so the dispatched `registry-host-replace` (a `workflow_dispatch`) is unaffected. No commit carries an `[ack-destroy]` line; `git log origin/main..HEAD --format=%B | grep -c 'ack-destroy'` must print 0.
- PR 9795: remove the WIP title; body states `Ref #9252` and `Ref #9390` (no closing keyword), the delivery model, the rollback values, and ends with the Generated-with-Claude-Code line.
- Hard gate before `gh pr ready`: `zot_mirror_asset_sha256_amd64` differs from the v2.1.20 value `05b171f2...`, and `--check-asset` on the branch is CLEAR for the new asset. Misordering is otherwise caught only by P6 after the merge.
- The PR body records the 2026-10-08 observation that both apply workflows read `active`, and says that the deferred running-host delivery of copy B will land on the next push apply that includes those resources.
- Mark ready, enqueue with the normal merge path. Do not sync a queued PR. A branch that is BEHIND is enqueued anyway; wait.
- Before enqueue, run the full local preflight once more (read-only): `GH_TOKEN="$(gh auth token)" doppler run -p soleur -c prd_terraform -- bash scripts/registry-replace-preflight.sh` and attach the verdict line to the PR. It is an early reading; the dispatcher re-runs it.

### Phase 7 — Delivery and verification (post-merge; section below)

## Delivery Runbook (post-merge)

**Route.** The merge to `main` fires `registry-host-replace-dispatch.yml` on its `push` trigger (paths include `zot-registry.tf` and `cloud-init-registry.yml`). That is the sanctioned route and the only one used. The pipeline does not fire a second dispatch while it runs (double-replace hazard); `concurrency: registry-host-replace-dispatch` de-duplicates, and the apply workflow's `terraform-apply-web-platform-host` group serializes.

**What the run does, in order, and what each gate means.**

| Step | Meaning if it holds | If it is red |
|---|---|---|
| `gate`: render at the watermark vs head | The bytes that reach the host changed (expected: yes). `deliver=true` | `deliver=false` on this PR means the render did not change: stop and report (the diff is not what Phase 4 step 11 proved). `kind=gate-failed`: compare API unreadable, render unmeasurable or over 32,768 B: read its `::error::`, stop and report |
| preflight P0 | Better Stack query credentials readable; fails closed | Stop and report; do not retry blind |
| P1 | No sustained local-cache pulls in 24 h: the fleet is not already living off its last tier (#6400 hazard) | The fleet is already degraded. Stop and report. The manual arm's `--manual` skips only P1: never used without an explicit new go from the operator |
| P2 | Advisory only (emitter unreachable since #7071) | Never gates; ignore |
| P3 | No release run in flight (a release may be mid-pull from the host about to be destroyed); waits up to 2100 s | Times out: a release is stuck; stop and report |
| P5 | The replace will be observable: control + container-log channel both return rows | `--manual` does not skip it: a dark channel means the outcome cannot be read back. Stop and report |
| P6 | The boot asset named by the render exists and carries sha256 T | Phase 3 was skipped or T is wrong. Stop and report; fix by publishing, never by editing the preflight |
| dispatch | Fires `apply-web-platform-infra.yml --ref main -f apply_target=registry-host-replace -f reason=...` | `dispatch-failed`: an apply may still have queued; read the apply workflow's run list before anything else |
| apply job (`registry_host_replace`) | `environment: infra-privileged` (no reviewer; branch policy admits `main` only); P6 again; plan with `-replace=hcloud_server.registry` and 5 `-target`s; `registry_host_replace_gate` (exact scoped recreate, `hcloud_volume.registry` not deleted/forgotten, private NIC create present); `stock_preflight_gate` (Hetzner reports the server type orderable in the location); apply; post-apply jq assertions | Any abort: nothing destroyed if it is before apply. `class=stock` means wait for stock; `class=config|malformed|unreachable` have their own advice in the abort line. Stop and report; there is no `[ack-destroy]` bypass on this path and none is ever added |
| poll (1500 s) and verdict | The dispatcher records the apply's conclusion on the PR | `apply-failed`: the host may be dark and the volume is preserved. Read the apply step's `recovery-read` block first. Stop and report; a re-dispatch is a second destroy-first replace on the sole pull path and needs an explicit go |

**Inputs.** Push arm: none. Manual re-fire (only after the refusing predicate is resolved): `gh workflow run registry-host-replace-dispatch.yml -f reason='<why>' -f tracker=9795`. Direct route (documented for a registry dark over 24 h, not planned): `gh workflow run apply-web-platform-infra.yml -f apply_target=registry-host-replace -f reason='<why>'`. There is no `confirm`, no `web_host_key`, and `plan_only` is not honoured by this target.

**Rehearsal.** `plan_only` does not exist for this path, so the rehearsal is: Phase 4 step 11 (offline render diff), PR-time `zot-image-mirror` `rehearse` on three image stores against the real asset, and the local read-only preflight in Phase 6. The apply job's own plan-shape and stock gates are the last gate before apply.

**Red-gate protocol (any gate, any step).** Stop. Do not re-fire, do not add `--manual`, do not edit a gate or the preflight, do not add `[ack-destroy]`, do not run a plain `web-host-replace`, the web-2 volume rebirth, or any web-1 / git-data target, do not delete a `zot-image-*` release. Record the run URL, the verdict `kind` and the predicate, post them on PR 9795 and #9390 (non-destructive comments), and report. Read-only diagnosis is allowed. Next actions are the runbook's (`registry-host-replace-dispatch.md`), taken only on an explicit go.

**If a push apply runs anyway** (the kill-switch lines did not survive): read-only. Open the run, record its URL on PR 9795, confirm from its log which `terraform_data` resources it touched and that no `hcloud_*` resource changed. Do not cancel it mid-apply, do not re-fire it, report. The expected effect is bounded: an idempotent hosts-file append with a post-deny resolution assertion on web-1/web-2, and a comment-only `ci-deploy.sh` redelivery. A failed assertion taints only the `terraform_data` resource.

**Timebox.** The dispatcher's own ceilings are P3 2100 s and the apply poll 1500 s. If no `zot_image_fetch=ok` row newer than the apply's conclusion appears within 60 minutes of that conclusion (the host's fetch retries for up to about 35 minutes), treat it as red: stop and report on PR 9795 and #9390 with the latest row's `zot_image_fetch` value.

**Soak (numeric, read from the same telemetry).** Over the 24 hours after the replace: `zot_restarts=0`, no `zot_last_err` row at error or fatal level, the next release's `crane copy` to zot completes inside its window, and the `zot-fill-rate-7341` follow-through (which waited on zot#4235, fixed by #4236 in v2.1.21+) is read for a changed outcome. A failure of any of these is reported, not auto-reverted (see Rollback).

**Verify the new host from telemetry (no SSH).**

```bash
doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 2h --grep SOLEUR_ZOT_DISK --limit 5
```

Healthy means a row newer than the apply's conclusion with `zot_image_fetch=ok`, `zot_image_digest=46f688dc2631` (D12 of the pinned manifest; re-derive from the final pin), `ghcr_blocked=1`, `state_status=running`, `zot_restarts=0`, `store_luks=yes`. `docker.pkg.github.com` has no per-name field, and `ghcr_blocked` probes `ghcr.io` only, so it reads identically on the old and new render. What it proves is that the deny entry ran and ghcr.io is sinkholed; `zot_image_digest=<final D12>` proves the NEW render booted. The proof that the third name is denied on the registry host is R10 (the rendered entry executed against a re-rooted hosts file) plus the Phase 4 step 11 render diff. #9390 is closed on those, with the limit stated in the closing comment. Also read the `soleur-registry-disk-prd` heartbeat status (best effort). Any other `zot_image_fetch` value: use the table in the runbook's "zot boot image" section, and stop and report.

**Close-out.** Comment the evidence on #9390 and close it. #9252 stays open until PR 9783 lands (then the next rule-audit poll sees both pins current). File one tracking issue for the deferred running-host delivery of copy B (decision D1), with re-evaluation criteria "the next push apply (or manual apply) that includes `zot_consumer_probe_install` or `deploy_pipeline_fix_web2`, which will deliver it unannounced; close when state carries the new hash", milestone from `knowledge-base/product/roadmap.md`, `Ref #9390`. The issue body also says that the 12-hourly `scheduled-terraform-drift` run will report `triggers_replace` drift for `zot_consumer_probe_install` and `deploy_pipeline_fix_web2` until then, so a drift report is expected, not a regression.

## Rollback

The superseded pin's asset is immutable and published, so P6 passes for it. Revert the four values (`zot_image_amd64`, `zot_image_arm64`, T, C) from the sidecar's previous-known-good block, plus the deny list if wanted, in one revert PR; the dispatcher sees the render change and replaces the host back. Decision rule: roll back only when `zot_image_fetch` is `id_mismatch` or `load_failed` after one re-fire, or the soak fails, and only on an explicit go. A revert is a second destroy-first replace and is subject to the same gates (including stock). If the push-arm run is refused on P1 because deploys fell to local-cache during an outage, the documented route is the manual arm, which needs an explicit go.

## Downtime & Cutover

**Operation and surface.** `registry-host-replace` destroys and recreates `hcloud_server.registry`, the host that serves the fleet's sole pull path. While it is down: running web and inngest containers keep serving (they do not pull at runtime), deploys fail at the pull step and wait, and a fresh web-host boot fails at its pull stage. The zot store volume is preserved and reattached, so no image is re-uploaded.

**Zero-downtime path evaluated, and why it is not available.** Blue-green (a second registry host live before the cutover) is not possible here: the store is one LUKS volume attached to one host at a time, ADR-096 and ADR-169 decide a single registry host with no tier beneath it (the host-to-GHCR fallback was retracted in #7071), and the host is cloud-init-only, so an in-place change does not exist (`user_data` is ForceNew). Drain-then-act IS available and is built in: P3 refuses to start while a release run is in flight, P1 refuses when the fleet is already on its last tier, and the stock gate refuses before the destroy when Hetzner reports the server type unorderable.

**Bounded window and sign-off.** The window is the apply job plus the host's boot and bounded asset fetch (the fetch retries up to about 35 minutes; the 60-minute timebox in the Delivery Runbook is the stop line). The dispatcher's push runs of 2026-09-28 and 2026-09-30 concluded success through the same route. The operator approved this replace on 2026-10-08 (brief: "The operator has explicitly approved BOTH the code change and the production registry-host replace apply (2026-10-08)").

**Per-stage verification and rollback.** Verification: preflight CLEAR before; plan-shape and stock gates before apply; post-apply store-volume-preserved and NIC-create assertions; telemetry row after. Rollback: Rollback section (revert the four values; the previous asset is published and immutable).

## Infrastructure (IaC)

### Terraform changes
No new resource. Edits to existing locals in `zot-registry.tf` and `server.tf`; no provider or version change; no new variable or secret.

### Apply path
(b) `terraform apply -replace` of `hcloud_server.registry` through the existing dispatcher and `registry_host_replace` job: destroy-first, store volume preserved, expected outage window of the registry only (tens of minutes; running containers keep serving, deploys wait). Not a user-run step: the pipeline performs it on merge.

### Distinctness / drift safeguards
Registry-only `-target` set; `hcloud_server.web` keeps `ignore_changes=[user_data]`, so copy A reaches fresh web hosts only. Copy B edits `triggers_replace` of two `terraform_data` SSH resources (web-1, web-2): see D1.

### Vendor-tier reality check
Hetzner stock for the registry server type in its location is the one live uncertainty; `stock_preflight_gate` reads Hetzner's `locations[].available`. A `class=stock` abort happens before the destroy.

## Observability

```yaml
liveness_signal:
  what: "SOLEUR_ZOT_DISK heartbeat rows (zot_image_fetch, zot_image_digest, ghcr_blocked, state_status) plus the soleur-registry-disk-prd Better Stack heartbeat"
  cadence: "every 5 minutes"
  alert_target: "Better Stack heartbeat incident; registry-host-replace-dispatch verdict comment on the delivering PR"
  configured_in: "apps/web-platform/infra/cloud-init-registry.yml (emitter) and apps/web-platform/infra/zot-registry.tf (heartbeat resource)"

error_reporting:
  destination: "Better Stack log source 2457081 via the registry container-log shipper; dispatcher verdict comment on the PR"
  fail_loud: "zot_image_fetch other than ok, ghcr_blocked other than 1, or state_status other than running; a refused or failed verdict kind on the PR"

failure_modes:
  - mode: "boot asset missing or wrong sha256 (P6)"
    detection: "preflight P6 refuses before any destroy; zot_image_fetch=sha_mismatch or download_failed on the host"
    alert_route: "dispatcher verdict comment (refused) and the liveness heartbeat going absent"
  - mode: "Hetzner stock short for the registry server type"
    detection: "stock_preflight_gate abort line with class=stock, before apply"
    alert_route: "apply run failure and the dispatcher verdict comment"
  - mode: "new host boots but zot does not start (id_mismatch, load_failed)"
    detection: "zot_image_fetch value in the SOLEUR_ZOT_DISK row; liveness heartbeat absent"
    alert_route: "Better Stack heartbeat incident"
  - mode: "hosts-file deny not in force on the registry host"
    detection: "ghcr_blocked=0 or unknown in the heartbeat row"
    alert_route: "Better Stack alert on the heartbeat field"

logs:
  where: "Better Stack source 2457081 (SOLEUR_ZOT_DISK rows, container logs)"
  retention: "Better Stack retention for the source"

discoverability_test:
  command: bash scripts/betterstack-query.sh --since 2h --grep SOLEUR_ZOT_DISK --limit 5
  expected_output: zot_image_fetch=ok
  credentials_required: "Doppler soleur/prd_terraform Better Stack ClickHouse read credentials: Better Stack log rows have no unauthenticated read path, so no unauthenticated probe verifies the same property"
```

## Encryption Posture

No persistent store is introduced and none is modified; this section exists because the plan edits `.tf` and cloud-init files. The existing registry store and the one connection this change touches are stated so the posture is on record.

```yaml
at_rest:
  - store: hcloud_volume.registry
    mechanism: luks
    evidence: "scripts/encryption-posture-ledger.json row hcloud_volume.registry (guest LUKS2; cryptsetup luksFormat and luksOpen anchors in apps/web-platform/infra/cloud-init-registry.yml; key from random_password.registry_luks via Doppler soleur-registry/prd). Unchanged by this plan; the volume is preserved by the replace."
    defends_against: "theft or snapshot of the detached Hetzner volume, and reading the volume from another host without the Doppler-held key"
    does_not_defend: "a compromised running registry host (the volume is unlocked while mounted), a compromise of the Doppler soleur-registry config that holds the key, and the image contents being non-secret by design (public and CI-built images)"
    disclosed_as: "ADR-096 and the encryption-posture ledger row"
    live_verification: "store_luks=yes in the SOLEUR_ZOT_DISK heartbeat row (#8386), read in the post-replace telemetry check"
in_transit:
  - connection: "registry host boot downloads the zot boot asset from github.com release assets"
    tls: "HTTPS (curl against the release URL derived in zot-registry.tf)"
    cert_verification: on
    does_not_defend: "a compromise of GitHub's release hosting that also reproduces the pinned sha256 T (not feasible by construction), and traffic metadata visible to the network path"
    disclosed_as: "ADR-096 amendment 2026-09-28 part 2: the host refuses any bytes other than T and any loaded image ID other than C or D"
```

## Guard Contract

### Guard 1 — hosts-file deny name-set parity

**Property.** Every copy of the ghcr hosts-file deny that can reach a host names exactly the same three hosts in the same order, and the executed effect on a re-rooted hosts file is one `0.0.0.0` line and one `::` line per name.

**Assembly.** Copy R (`cloud-init-registry.yml` runcmd entry), copy A (`cloud-init.yml` runcmd[1], rendered on both `web_tunnel_connector` arms), copy B (`server.tf` `ghcr_deny_sh` and `ghcr_deny_assert_sh`, consumed by `zot_consumer_probe_install` and `deploy_pipeline_fix_web2`), plus the test-side literals in `web-ghcr-deny.test.sh`, `zot-image-fetch.test.sh` and `cloud-init-ghcr-seed-login.test.sh`. The chokepoints are the parsed render (yaml of the rendered template, terraform console for the locals), the census over infra `.tf/.sh/.yml/.tmpl`, and the executed-effect rows; a copy added in a fourth place is caught only by the census, so the census regex is part of the assembly.

**Mutation matrix** (rows 1, 2, 3, 5 are new in this PR; 4 extends an existing floor; 6 and 7 already exist):

| # | Mutation | Expected |
|---|---|---|
| 1 | drop the third name from copy R only | RED (parity R vs A vs B) |
| 2 | drop the third name from `ghcr_deny_assert_sh` only, deny loop unchanged | RED (agree row: shim resolves the third name to a real address and the assertion must FATAL) |
| 3 | add a fourth name to copy A after the compliant first three | RED (parity; a check that stops at the third name is the defect) |
| 4 | the suite's render step returns zero entries (the guard's own dispatch) | RED (count floor on rendered entries per arm; "0 checked" is a failure, not a pass) |
| 5 | reorder the names in copy B only | RED (whole-entry byte parity) |
| 6 | suite edit: make `same()` always true (existing harness row; keep) | RED (the comparator is load-bearing) |
| 7 | must-PASS non-canonical input: copy A re-indented, same parsed entry (existing harness row; keep) | PASS |

**Anchor.** Parity proves the copies agree, not that three names is the right set. The independent anchors are the literal expected-name lists in two separate suites (`web-ghcr-deny.test.sh` `HDR` and `zot-image-fetch.test.sh` R10) and the ADR-096 amendment text; a coordinated weakening needs edits in all three. No anchor outside the commit exists; that residual is stated, not closed.

The pin-freshness gate (`zot-image-staleness.test.sh`, 15 checks plus its mutation battery) is existing machinery extended by data only; it needs no new contract entry. The network half of the anchor for T and C is the PR `rehearse` rebuild and P6, which is why Phase 3 precedes the merge.

## Architecture Decision (ADR/C4)

No new decision: the boot-asset design, the deny mechanism and the replace authorization are decided in ADR-096 (2026-09-28 part 2), ADR-169 and ADR-190. Tasks: dated amendment lines in ADR-096 and ADR-169 (Phase 5, ADR-096 only). C4: read all three of `model.c4`, `views.c4`, `spec.c4` at work time; no actor, external system, container or access relationship changes (the registry host, its Cloudflare edge, GHCR and GitHub release assets are already modeled; `docker.pkg.github.com` is a blocked name, not an edge), and `plugins/soleur/test/c4-count-parity.test.sh` must be green as the count-parity backing for "no C4 impact".

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "issue #9252 (zot pin v2.1.20 -> current upstream" [brief] | Phases 1-3 | mapped |
| 2 | "issue #9390 (add docker.pkg.github.com to the host hosts-file GHCR deny)" [brief] | Phase 4 | mapped |
| 3 | "delivered as ONE bundled registry-host replace" [brief] | Delivery Runbook | mapped |
| 4 | "(1) rotate the previous-known-good pin" [brief] | Phase 1 step 1 | mapped |
| 5 | "(2) resolve BOTH arch digests (amd64 and arm64)" [brief] | Phase 1 step 2 | mapped |
| 6 | "(3) re-diff the four upstream anchors" [brief] | Phase 2 step 3 | mapped |
| 7 | "(4) re-measure the 200-or-401 claim" [brief] | Phase 2 step 4 | mapped |
| 8 | "(5) publish the boot asset via zot-image-mirror.yml BEFORE the bump merges" [brief] | Phase 3 | mapped |
| 9 | "(6) pin zot_mirror_asset_sha256_amd64 and zot_config_digest_amd64" [brief] | Phase 3 | mapped |
| 10 | "(7) the hosts-file deny edit at every byte-identical site" [brief] | Phase 4 | mapped |
| 11 | "the replace is performed ONLY through the sanctioned path" [brief] | Delivery Runbook route | mapped |
| 12 | "rehearsing with plan_only first where the path supports it" [brief] | Delivery Runbook rehearsal (path does not support it) | mapped |
| 13 | "verifying the new host healthy from telemetry with no SSH" [brief] | Delivery Runbook verify | mapped |
| 14 | "state exactly which dispatch route, inputs, interlocks and preflight apply, what each held interlock means, and what to do on ANY red gate" [brief] | Delivery Runbook tables | mapped |
| 15 | "never add an [ack-destroy] line to any commit body" [brief] | Phase 6, AC | mapped |
| 16 | "do not touch the web-1 or git-data hosts" [brief] | D1, AC | mapped |
| 17 | "use `Ref #9252`, never Closes" [brief] | Phase 6 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| zot-registry.tf, provenance sidecar edits | "resolve BOTH arch digests" / "rotate the previous-known-good pin" | asked |
| cloud-init-registry.yml, cloud-init.yml, server.tf, web-ghcr-deny.test.sh, zot-image-fetch.test.sh | "the hosts-file deny edit at every byte-identical site the issue #9390 lists" | asked |
| cloud-init-ghcr-seed-login.test.sh | — | inferred — justification: it holds a literal copy of the deny entry and splices the header in mutation rows; without the edit its suite reddens (enforcement contract) |
| ci-deploy.sh, ci-deploy.test.sh and cloud-init-registry.yml comment claims | "re-measure the 200-or-401 claim" | asked (staleness check 7 reads all three followers and requires each to name the pinned version) |
| scripts/followthroughs/zot-fill-rate-7341.sh wording | — | inferred — justification: it states "zot#4235 is unfixed in v2.1.20"; the fix PR #4236 is in v2.1.21+, so the sentence turns false the moment this replace lands, and its FAIL message would mislead the next reader |
| Step 3b breaking-change scan | — | inferred — justification: the four anchors do not cover #4363, which measurably changes cross-repo HEAD under `dedupe: true`; the sidecar's procedure would otherwise miss it next time |
| Kill-switch lines D1 | "do not touch the web-1 or git-data hosts" | asked |
| ADR-096 dated amendment line | — | inferred — justification: that ADR states the deny's two names, which this change makes false; recorded architecture must not lag |
| decision-challenges.md, tasks.md | — | inferred — justification: pipeline contract (headless decisions persist; tasks derive from the plan) |
| Running-host delivery tracking issue | — | inferred — justification: a deferral without an issue is invisible (`wg-when-deferring-a-capability-create-a`) |

### Split Assessment

- Subsystems touched: 2 — `apps/web-platform`, `knowledge-base`
- Planned files: 16 | Estimated changed lines: ~400
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 `bash apps/web-platform/infra/zot-image-staleness.test.sh` exits 0 at the new version, and `zot-image-staleness-mutation.test.sh` is green.
- [ ] AC2 Both digests in `zot-registry.tf` equal a fresh `crane digest` / anonymous-token resolution at the final tag, arch-keyed, and differ from each other.
- [ ] AC3 `## Previous known-good pin` holds the v2.1.20 refs in tag-less form for both arches, plus the v2.1.20 release tag, T and C.
- [ ] AC4 The four anchors are re-diffed and the table updated; the breaking-change scan is recorded with the #4363 measurement (cross-repo HEAD 200 to 404, mount unchanged) and the shared-layer answer; `hydrateBlobOnRead` recorded NOT ADOPTED in the sidecar, or the STOP rule fired and the PR was not marked ready.
- [ ] AC5 The 200-or-401 and gc-404 claims are re-measured against the final digest with the exact config; zero 403; claim dates updated in the sidecar, `cloud-init-registry.yml`, `ci-deploy.sh` and `ci-deploy.test.sh`; `zot-fill-rate-7341.sh` reworded.
- [ ] AC6 (hard gate before `gh pr ready`) Release `zot-image-<final version>-<D12>` exists, published before the PR is marked ready; `GH_TOKEN="$(gh auth token)" bash scripts/registry-replace-preflight.sh --check-asset` prints `verdict=CLEAR predicate=P6`; T and C are pinned; the PR's three `rehearse` jobs are green.
- [ ] AC7 All seven deny sites carry the same three names; `web-ghcr-deny.test.sh`, `zot-image-fetch.test.sh`, `cloud-init-ghcr-seed-login.test.sh` are green; `git grep -n "for h in ghcr.io"` shows no unreviewed copy.
- [ ] AC8 Registry render at HEAD vs `origin/main` differs only by the pin-derived values and the deny line; stored size headroom stays above 10,000 B; `registry-render-delta.test.sh`, `registry-userdata-budget.test.sh`, `registry-boot-guard.test.sh`, `cloud-init-user-data-size.test.ts`, `ci-deploy.test.sh` green.
- [ ] AC9 `git diff origin/main --name-only` lists no `.github/workflows/` path and not `.mcp.json`; `git log origin/main..HEAD --format=%B | grep -c 'ack-destroy'` prints 0; one commit message has `[skip-web-platform-apply]` and `[skip-deploy-fix-apply]` each on its own line.
- [ ] AC10 PR body: `Ref #9252`, `Ref #9390`, no closing keyword; ends with the Generated-with-Claude-Code line; the commit trailer is the Claude Sonnet 5.5 Co-Authored-By line.
- [ ] AC11 `python3 scripts/lint-guard-contract.py` and `python3 scripts/lint-infra-no-human-steps.py <this plan>` pass.

### Post-merge (automated; the agent reads, does not trigger)

- [ ] AC12 The dispatcher run for the merge SHA concluded with the dispatched apply run `success`; no second registry dispatch was fired.
- [ ] AC13 The telemetry command shows a post-apply row with `zot_image_fetch=ok`, the final D12 as `zot_image_digest` (the new render booted), `ghcr_blocked=1` (the deny entry ran; ghcr.io only), `state_status=running`. The third name's proof is AC7 plus AC8, not this row.
- [ ] AC14 (detective only; the preventive check is the pre-enqueue `git log origin/main..HEAD --format=%B | grep -x '\[skip-web-platform-apply\]'` and the same for `[skip-deploy-fix-apply]`) For the merge SHA, the `apply-web-platform-infra.yml` and `apply-deploy-pipeline-fix.yml` push runs show their `preflight` skip=true (the kill-switch lines survived the squash); confirmed with `git log -1 --format=%B <sha> | grep -x '\[skip-web-platform-apply\]'`.
- [ ] AC15 #9390 closed with the evidence comment; #9252 still open with a comment linking the result; the running-host delivery issue exists.

## Domain Review

**Domains relevant:** Engineering, Operations

### Engineering
**Status:** reviewed
**Assessment:** Infra-only. Highest-risk element is the destroy-first replace on the sole pull path; mitigated by existing gates, P6-before-merge ordering, and an explicit stop-and-report protocol. The v2.1.21 breaking change (#4363) is a plan-time finding the stock bump procedure would have missed.

### Operations
**Status:** reviewed
**Assessment:** No new vendor, account or cost. Registry replace is an existing automated path; the apply workflows being re-enabled today changes merge-time blast radius, handled by D1.

## Test Scenarios

- Deny parity: render both arms, assert three names in R, A, B; execute B and R-entry twice on temp files (idempotent, unrelated lines untouched, pre-seeded TAB entry not duplicated for the first name, the new name appended once).
- Agree: getent shim resolves the third name to a real address, so copy B's assertion FATALs; resolves only to the sinkhole, it passes; unresolvable fails.
- Staleness: the 15 existing checks pass at v2.1.22; mutation battery stays red where designed.
- Render: HEAD vs `origin/main` stripped registry user_data differ in exactly the expected hunks.
- Asset: P6 clear for the new asset; P6 refuses when T is mutated (local mutation of the pin in a scratch copy, never committed).
- Delivery (post-merge, observed, not rehearsed): dispatcher gate true, preflight CLEAR, apply success, telemetry healthy.

## Risks

- **R1 Stock.** Destroy-first replace; `class=stock` aborts before the destroy, but a flip between gate and create strands the host (volume preserved). Mitigation: gates; rollback needs a second successful create.
- **R2 128-commit delta.** The sidecar's earlier bump was a two-commit delta; this one is not. Mitigation: step 3b, the measured matrix, post-replace soak signals (restarts, `zot_last_err`, retention behaviour).
- **R3 Cross-repo HEAD change.** Slower CI pushes of shared layers; STOP rule in step 3b.
- **R4 Kill-switch lines not surviving the squash.** Then the push applies reach web-1/web-2: an idempotent hosts append with an assertion over SSH, plus a comment-only `ci-deploy.sh` redelivery through the webhook to web-1 (its swap is gated on a seccomp verdict). Low probability (the squash composition was verified from merged commits) and the effect is small but not nil; AC14 reads it; no cancellation mid-apply.
- **R5 Newer upstream release before merge.** Re-read the latest release at the start of Phase 1 and once more immediately before the Phase 3 dispatch; if it moved before the dispatch, redo Phases 1 to 3 for the new tag. After the asset is published, ignore newer tags and file a follow-up unless a security advisory applies. Abandon path: close the PR, leave the published release (never delete it), say so on #9252.
- **R6 `.mcp.json`** is modified locally and unrelated: never `git add -A`.

## Decision D1 (persisted to decision-challenges.md)

The brief asks for edits to copy B (`server.tf`) and `ci-deploy.sh`, and also says "do not touch the web-1 or git-data hosts". Both files feed `triggers_replace` of SSH `terraform_data` resources that now fire on merge. Default (operator constraint wins): the two kill-switch lines keep the push applies from running for this merge, so the running-host delivery of copy B waits for the next sanctioned apply (tracked). Alternative: omit the lines and let the merge deliver to web-1 and web-2 now. The registry replace is unaffected either way.

## Sharp Edges

- `plan_only` does not apply to `registry-host-replace`; do not reach for it, and do not edit `apply-web-platform-infra.yml` to add it.
- The previous-known-good rows must be tag-less (`zot-linux-<arch>@sha256:`); a tagged form fails staleness check 8.
- Commit A must land and be pushed before the mirror dispatch; commit B (T, C) must land before marking ready.
- A kill-switch line counts only in a branch commit message, never the PR body.
- Never `git add -A`; a stray `.mcp.json` local modification may reappear.
- The `ci-deploy.sh` comment edit changes the host-scripts content hash that fresh web hosts re-verify against the baked image: the next web-host birth or replace must use an image built from a commit at or after this one.
- Do not add `${` or `%{` to the `ghcr_deny_*` heredocs; they must render literally.
- Local `apps/web-platform/node_modules` is stale: rely on CI for typecheck. Shell suites run locally.
- Always `cd <worktree> &&` in Bash calls; no `pkill -f`; no `git stash`.
- A plan whose `## User-Brand Impact` section is empty or filler text fails deepen-plan; this one is filled.

## Resume

`soleur:work knowledge-base/project/plans/2026-10-08-chore-zot-pin-v2-1-22-and-docker-pkg-github-deny-registry-replace-plan.md`. Branch `feat-one-shot-9252-zot-pin-bump-ghcr-deny`, worktree `.worktrees/feat-one-shot-9252-zot-pin-bump-ghcr-deny`, PR 9795, issues 9252 and 9390.
