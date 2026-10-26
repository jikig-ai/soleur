---
title: "chore(inngest): trim cloud-init-inngest.yml user_data by at least 500 B before the next host replace"
date: 2026-10-26
slug: trim-inngest-user-data-before-host-replace
branch: feat-one-shot-11080-inngest-userdata-trim
issue: 11080
closes: 11080
type: chore
domain: engineering
priority: p2-medium
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
lane: cross-domain
---

# Plan: trim the Inngest host `user_data` by at least 500 B (#11080)

## Overview

The Inngest host's rendered `user_data` sits 280 B under Hetzner's 32,768 B cap on current main. The replace precondition ruled in T4 needs at least 300 B of CI-rendered margin, and issue #11080 asks for a separate trim of at least 500 B so that margin is reached with room for the next edits. This plan trims `apps/web-platform/infra/cloud-init-inngest.yml` and nothing else on the delivery path, measured offline at 520 B removed (headroom 280 B to 800 B), clearing the ruled floor of 780 B.

Three kinds of text go, and none of them is host logic:

- **A. Dead references to the retired LUKS cutover trio** (148 B). Image `vinngest-v1.1.61` is the merge commit of #10966, which deleted `inngest-luks-cutover.{sh,service,timer}` from the bootstrap image. The template still stages the trio, quiesces it, polls its service and writes the one environment file only it read. `inngest-carrier-vocabulary.test.sh` already says those references stay "until the user_data PR lands".
- **B. Five unit `Description=` strings no test quotes** (100 B).
- **C. Four logger message tails** that are explanatory prose after an em dash (272 B). The prose moves into `#` comment lines directly above each message, which the render strips for free, so the knowledge stays in the source and the shipped markers, fields and `#7228` reference are unchanged.

The PR also extends the existing Guard 3 stem scan to cover `cloud-init-inngest.yml`, so change A cannot regress silently (ruling R3).

Hard constraints, carried from the owner's typed go ("land 11080 first", the trim PR through merge): this PR does not replace, dispatch or read anything on the Inngest host. The host replace, the resume and the flip each need their own typed go and are out of scope.

## Research Reconciliation - Spec vs. Codebase

| Brief or issue claim | Reality (measured 2026-10-26, `origin/main` 81192540bf) | Plan response |
|---|---|---|
| "the budget script reports raw 229,683 B, after strip 87,960 B, stored 32,488 B, cap 32,768 B, headroom 280 B" | Re-run in this worktree: identical figures, exit 0, 0.4 s. | Baseline confirmed; Phase 0 re-measures after the rebase. |
| "the CI render is larger than the offline measure by an amount nobody has measured" (#11080) | The CI job `inngest-userdata-budget` in `infra-validation.yml` runs the same script, whose stubs are length upper bounds; no other render of this payload exists on the merge path (the per-merge apply never plans the server, and the `lifecycle.precondition` fires only on the dispatch routes). For a branch rebased onto main the CI figure equals the offline figure. | AC1 gates on the script's own number; the PR body quotes the CI job log line once the job has run on the trial merge. |
| "check how the per-merge push apply treats it (the server_touched abort in apply-web-platform-infra.yml and the [skip-web-platform-apply] merge-commit marker)" | `server_touched` is a HALT of the dispatch-only `inngest_host` job (`apply-web-platform-infra.yml`, the shape-gate error text "hcloud_server.inngest would be updated or replaced"), not of the push path. The push apply's `-target` allow-list contains no `hcloud_server.inngest` and nothing in it references the server (only `hcloud_server_network.inngest` and `hcloud_volume_attachment.inngest_redis_luks` do, neither targeted); `terraform-target-parity.test.ts` pins that exclusion. Five earlier merges that changed this file (c15ed71796, e002f2bc47, bot pin bumps 4be03df110, 097d96208d, 81192540bf) each had a successful push apply with no marker; run 40262107186 for 81192540bf shows no `hcloud_server.inngest` in plan or refresh. | Ruling R2: no marker, a pre-merge gate and a post-merge apply-run read. See "Merge safety". |
| "the next replace also carries three `cloud-init-inngest.yml` commits not on the live host" | c15ed71796, e002f2bc47 and dc9391d11c are on main; the render of a trial merge includes them and the v1.1.61 digest (T4). | Nothing to do here; the trial-merge measurement already includes them. |
| "a user_data edit force-replaces `hcloud_server.inngest`" | True for the resource (no `ignore_changes` on `user_data`, ADR-100). It is inert at merge and visible only to the unscoped PR-time `infra-validation` plan and the drift detector, which already show the replace because of the earlier commits. | The PR body says the PR-time plan will show the host as replaced and that this is known drift, informational. |
| "comments, duplicated blocks, content that could move into the image or the render-stripped prose region" | Whole-line `#` comments are already stripped before gzip (0 B to gain); the render has 0 trailing comments and 0 surviving `#` lines other than shebangs. Duplicated blocks compress to a few bytes each (gzip), so a helper refactor gains under 60 B. Moving scripts into the image needs a new image generation, a pin bump and another replace. | Cut; see the Cut List. Only unique non-comment text is worth trimming, and prose moved into stripped comments is the cheapest form. |
| (research hand-back) "the TS budget `INNGEST_GZIP_BUDGET = 32_300` is below the script's 32,488 B" | Not a discrepancy: that constant is a binary gzip-size ceiling (about 24.4 kB for this render), not the base64 stored size the script reports. | None; ruling note P3. |

## Research Insights

### Premise Validation (Phase 0.6)

Checked: issue #11080 is OPEN with no closing PR; ruling T4 text read in the archived decision table; `inngest-userdata-budget.sh` and `cloud-init-inngest.yml` exist on `origin/main`; the `server_touched` and marker mechanics read in `apply-web-platform-infra.yml` (marker anchored at the preflight job, `(^|\n)\[skip-web-platform-apply\]($|\n)` against `github.event.head_commit.message`); the repo squash setting read with `gh api` (`squash_merge_commit_message = COMMIT_MESSAGES`, `squash_merge_commit_title = COMMIT_OR_PR_TITLE`, so a marker would have to be its own line in a branch commit body, and the 2026-10-01 learning that says the body comes from the PR body is stale on this point); ADR corpus checked for the mechanism (ADR-152 strip pattern, ADR-185 sibling headroom policy, ADR-100 no `ignore_changes`; none rejects a template trim). Held: all of the above. Stale: the brief's "CI render larger than offline" premise (see the reconciliation table) and the PR-1 plan's expectation that PR-D would also add the keeper trio to STAGED (the keeper PR has not merged, so nothing is added here).

### Property List and Cut List (Phase 0.6b)

Properties the ask needs, each observable:

1. The stored `user_data` of a trial merge is at most 31,988 B, so the margin to the 32,768 B cap is at least 780 B (500 B trimmed, ruled floor).
2. A host created from the trimmed template behaves as before: same units, same scripts' logic, same markers and fields.
3. Merging the PR cannot replace, reboot or dispatch anything on the Inngest host.
4. The trimmed references cannot quietly return.

| Mechanism in the ask | Property it buys | Already on main? |
|---|---|---|
| Trim `cloud-init-inngest.yml` | 1 | The strip already removes comments; code has to go. |
| Check the per-merge apply (`server_touched`, marker) | 3 | The `-target` allow-list and `terraform-target-parity.test.ts` already buy 3; the plan verifies rather than builds. |
| Make the merge safe | 3 | Same; plus a pre-merge gate and a post-merge read (R2). |

Cut List (mechanism, property, what already covers it): marker on the merge commit -> property 3 -> the `-target` exclusion plus parity test already prevent a planned replace, and the marker adds a line-anchoring failure mode (R2). Wider strip regex in `inngest-host.tf` -> property 1 -> rejected, changes a semantic two suites assert and gains 160 B alone (R1, D). `--min-headroom 300` CI floor -> property 1 -> deferred to PR-D with a tracking issue (R3). Edits to `infra-config-install.sh` rows or `cosign-trusted-root.json` -> property 1 -> reach web-1 and web-2 through the push channel and the trust set, cut (P2). Dedup helper refactors -> property 1 -> gzip already dedups, under 60 B, cut. Moving scripts into the image -> property 1 -> new image, pin bump, another replace, cut. Trimming the fresh-boot LUKS pointer or unpointed arm -> property 1 -> which arm is live depends on a Doppler value this work may not read, cut (P1).

### Measured candidates (scratch copy of `apps/web-platform/infra`, edits applied cumulatively, headroom after each)

Command for every row: `bash inngest-userdata-budget.sh` run inside a scratch copy of the infra directory; the real tree was never edited.

| Step | Edit | Headroom (B) |
|---|---|---|
| base | none | 280 |
| A1 | STAGED list loses the three `inngest-luks-cutover.*` names | 292 |
| A2 | quiesce loop, stop line, busy-check loop, `frozen-active` line and service-status list lose the cutover timer, service and state path | 376 |
| A3 | the two lines that write and verify `/etc/default/inngest-luks-volumes` are deleted | 428 |
| B (all 7) | seven unit Descriptions shortened | 604 |
| B (5 untested) on top of A | five Descriptions shortened | 528 |
| C on top of A and B(5) | four logger message tails cut (marker and fields kept, `#7228` kept) | 800 |
| D (rejected) | blank lines removed from the template | about +90 |
| S (rejected) | `inngest_rationale_strip` widened to blank lines | +160 alone (280 to 440) |

The chosen set A + B(5) + C measures 31,968 B stored, 800 B headroom, 520 B trimmed, which is 20 B above the ruled floor of 780 B. The margin is thin (D, worth about 90 B, covers only a small shortfall and cannot replace C) and the figure is deterministic, so Phase 0 and the final gate re-measure after the rebase.

Pre-checks done on the chosen scratch tree: the `| grep -q` census count in the template stays 4; the `ZIREF=` and `IREF=` lines are byte-identical; the non-comment text has zero hits for the three trio stems (it has 6 today).

### Merge path findings (verified by reading, with run evidence)

- Push apply: `apply-web-platform-infra.yml` triggers on `apps/web-platform/infra/**` (this file is under it). The only `terraform_data` it re-runs because of this file is `terraform_data.zot_consumer_probe_install`, whose trigger hashes the digest read by `web-probe.tf` from the `ZIREF` line; the pin-bump merges change that line, a trim does not. Expected outcome for this merge: 0 changes.
- `apply-deploy-pipeline-fix.yml` (paths `server.tf`, `hooks.json.tmpl`, `infra-config-install.sh`, `infra-config-apply.sh`, `push-infra-config.sh`) does not fire, because this PR touches none of them. That is why the shared `infra-config-install.sh` is off limits.
- `mint-inngest-bootstrap-tag.yml` triggers on `apps/web-platform/infra/inngest*`; the files this PR touches that match are test files, which are not image carriers, so the mint decides "no carrier change" and mints nothing. `cloud-init-inngest.yml` does not match the path filter.
- `validate-vector-config.yml` and `infra-validation.yml` also run (advisory); `infra-validation`'s PR-time `plan` shows `hcloud_server.inngest` as replaced (unscoped plan, known drift).
- No workflow auto-dispatches `inngest-host-replace` (grep of `.github/workflows` and `scripts`).
- A second Terraform root renders the same template: `apps/web-platform/infra/inngest-provision-rehearsal/rehearsal.tf` calls `templatefile("${path.module}/../cloud-init-inngest.yml", ...)` with its own state and its own dispatch workflow (`inngest-provision-rehearsal.yml`), which a merge never fires (the apply workflow's path filter excludes that directory). This PR changes template text only and adds or removes no template variable, so the rehearsal's variable set stays valid; `inngest-provision-rehearsal.test.sh` joins the verification list for that reason. (Verified by the deepen-pass negative-claim sweep: no `terraform_data` hashes the file; no executing dispatch of `inngest-host-replace` exists; `hcloud_firewall_attachment.inngest` in the per-merge targets is only a `removed` block and pulls in nothing.)

### Institutional learnings applied

- `2026-07-07-cloud-init-user-data-cap-is-measured-on-the-gzipped-render.md`: measure the stored value, never `wc -c`; re-measure any quoted headroom.
- `2026-07-03-base64gzip-hetzner-user-data-and-discrimination-test-must-exercise-sut.md` and the `inngest-host.tf` strip comment: comment lines are free, only non-comment bytes count.
- `2026-07-26-cloud-init-comment-is-a-live-host-input-and-an-unreadable-vendor-limit-decays.md`: a comment can be read by something on the host; the moved prose is a whole-line `#` comment inside a shell script body, which the render strips before delivery, so it never reaches the host.
- `2026-10-06-which-files-feed-user-data-with-no-ignore-changes-decides-whether-a-mechanical-edit-is-a-host-replace.md`: run every suite that pins the old text, not just the file's own suite.
- `2026-08-04-my-guard-certified-a-string-in-a-file-not-the-render-that-boots.md` and `2026-07-19-my-own-mutation-battery-was-the-false-confidence.md`: the control must be green before a mutation row means anything; guards check the render.
- 2026-09-08 destroy-then-fail-to-create (documented only in the comments of `inngest-host.tf` and `inngest-userdata-budget.sh`): the destroy-guard and stock preflight do not weigh payload size, so the size gate is the only protection and the margin is worth having.

### Test surface (from the research pass; invocation, time, kind)

Required in CI (`test` aggregator): `plugins/soleur/test/cloud-init-user-data-size.test.ts` (rendered size under 32,300 binary gzip, above floor 26,000), `.claude/hooks/grep-q-pipe-guard.test.sh` (census row `cloud-init-inngest.yml | = | 4`), `scripts/lint-encryption-posture.py --repo-sweep` (luksFormat/luksOpen anchors, untouched), `tests/scripts/test-argv-bearer-sweep.sh` (the `pull-login` site, untouched). Advisory but pinning: `cloud-init-inngest-provision-unit.test.sh` (88 rows today: RED 79/79, must-PASS 9/9; about 4 min, the only suite that pins the quiesce loop), `cloud-init-inngest-zot-pull-mutation.test.sh` (about 90 anchor mutants, about 227 s), `cloud-init-inngest-bootstrap.test.sh`, `inngest-host.test.sh`, `inngest-boot-emitter.test.sh`, `inngest-carrier-vocabulary.test.sh` (52 assertions, about 8 s), `inngest-redis-luks.test.sh` and its loopback twin, `journald-config.test.sh`, `inngest-config-refresh.test.sh`, `cloud-init-ghcr-seed-login.test.sh`, `cloud-init-web-zot-seed.test.sh`, `web-zot-consumer-probe.test.sh`, `templatefile-bare-dollar-guard.test.sh`, `credential-persist-home-guard.test.sh`, `doppler-injection-bound.test.sh`, `inngest-nic-wait.test.sh`, `inngest-cutover-flip.test.sh`, `inngest-server-flip-guard.test.sh`. The affected-tests map has no entry for the template, so the work phase runs this list by hand.

Not pinned by any suite and still left alone: the sshd hardening drop-in, the package list, the nftables script body (security- or boot-relevant; "unpinned" is a coverage gap, not licence).

## Problem Statement / Motivation

A user_data over the cap makes the replace destroy the sole scheduler host and then fail to create it, and a re-dispatch cannot fix that (2026-09-08). Margin of 280 B is below the 300 B precondition and leaves no room for the keeper trio, the `LUKS_HDR_PUT` admission and the `fetch_rc=93` fix that follow. Nothing else on main buys the margin; the PR-1 prework deliberately left the `user_data` edits for a later PR.

## Proposed Solution

One edit file plus two test files, in this order (tests first, per `cq-write-failing-tests-before`):

1. **Guard 3 extension** (`apps/web-platform/infra/inngest-carrier-vocabulary.test.sh`): add `apps/web-platform/infra/cloud-init-inngest.yml` to `DELIVERY_FILES` (stem scan, whole-line `#` comments stripped, no vocabulary scan because the template's comments legitimately name retired paths), add the mutation rows of Guard Contract 1, and replace the header's "NOT COVERED (1)" paragraph with a statement that the file is now scanned. Against the unmodified template the real-tree row is RED with 6 stem hits, which is the failing test for change A.
2. **Quiesce battery adaptation** (`apps/web-platform/infra/cloud-init-inngest-provision-unit.test.sh`): re-point T4 at the flip timer, drop the Q2 and Q3 rows and the `luks-cutover` fixture state, keep Q1 and Q4 (flip service activating, flip flag flipping), keep Q5 shape with only the flip flag, re-point the two mutation anchors (`Q_OPEN` and the `rep_line("for _u in ...")` row G2-r14) to the new loop text, and update the row counts and header numbers by running the suite (the header says 83 rows while the suite reports 88; the work phase takes the real executed counts, never a remembered literal).
3. **Template edits** in `apps/web-platform/infra/cloud-init-inngest.yml`, measuring after each step:
   - A1: in `soleur-inngest-provision`, `STAGED="..."` drops ` inngest-luks-cutover.sh inngest-luks-cutover.service inngest-luks-cutover.timer` and keeps `cat-inngest-cutover-state.sh` (the flip FSM's own file).
   - A2: the quiesce block loops over `inngest-cutover-flip.timer` only, stops only that timer, checks only `inngest-cutover-flip.service` for `activating`, deletes the `[ -s /var/lib/inngest-luks-cutover/frozen-active ]` line, and the service-status list loses `inngest-luks-cutover.timer`. Rewrite the comment above the block (free, stripped) so it no longer says the LUKS cutover records a freeze.
   - A3: delete the `printf 'INNGEST_LUKS_ADDITIVE_VOLUME_ID=...' > /etc/default/inngest-luks-volumes` line and its `grep -qx` assertion, and the comment above them (it justifies the file for the retired cutover service). Keep `luks_emit luks_key_stage 0 n/a staged`.
   - B: shorten the Descriptions of `inngest-nftables.service`, `inngest-bs-token-restage.service`, `soleur-inngest-provision.timer`, `inngest-config-refresh.service` and `inngest-config-refresh.timer`. Candidate texts (re-measured at work time): "Inngest nftables scoping (SEC-H2)", "Re-stage the boot-trace token (#7228)", "Re-enter provisioning until it succeeds once (#8562)", "Apply the signed inngest config bundle (#6780)", "Fire inngest-config-refresh every 60 s (#6780)". The Descriptions of `inngest-luks-open.service` (quoted by `inngest-redis-luks.test.sh`) and `soleur-inngest-provision.service` (quoted by `scripts/followthroughs/inngest-provision-rehearsal-capture.test.sh`) stay untouched. Re-grep the five old strings across `*.test.*` immediately before editing.
   - C: in `inngest-boot-phone-home.sh` the three `SOLEUR_INNGEST_BOOT_TRACE_LOST` messages end at `reason=token-file-missing path=$tok_file #7228`, `reason=token-file-empty path=$tok_file #7228` and `reason=post-failed rc=$crc #7228`; in `inngest-bs-token-restage.sh` the failure message ends at `drc=$drc #7228`. The removed sentences go into `# ` comment lines directly above each `logger` line, with no `${` or `%{` sequence in them (templatefile reads comments too).
   - Runbook sync (unconditional, found by the deepen-pass observability review): the runbook has one `SOLEUR_INNGEST_BOOT_TRACE_LOST` row and nothing on `SOLEUR_INNGEST_BS_TOKEN_RESTAGE_FAILED`, and the comment lines are stripped from the render, so the cut tails would leave this diagnosis nowhere an operator can read it. Add a `reason=` sub-table under the `BOOT_TRACE_LOST` row (`token-file-missing`: expected after a reboot if the per-boot restage unit did not run, `/run` is tmpfs and cloud-init runcmd is first-boot only; `token-file-empty`; `post-failed rc=`: curl rc 6/7 egress, 22 revoked token, 28 timeout, 35/60 TLS) and a new `BS_TOKEN_RESTAGE_FAILED drc=` row (`drc=124` is the `timeout 20`; other values are doppler exit codes; consequence: `/run/inngest-bs-logs-token` is empty for the boot and every `SOLEUR_INNGEST_BOOT_STAGE` marker is lost; pointer to the restage unit).
4. **Measure and gate** (see Acceptance Criteria), then run the suites one at a time.

Out of scope, with reasons in the Cut List: any LUKS first-boot logic, `infra-config-install.sh`, `cosign-trusted-root.json`, `inngest-host.tf`, the strip regex, image changes, the `--min-headroom` floor, the keeper trio.

## Merge safety (ruling R2)

What the push apply does when a `user_data` edit would replace `hcloud_server.inngest`: nothing, because the resource is pruned by `-target`; the `server_touched` abort exists only on the dispatch path. The `[skip-web-platform-apply]` marker therefore buys no safety for this PR: it skips the push apply, it does not prevent a replace, and under `COMMIT_MESSAGES` squash it must sit on its own line in a branch commit body or it silently fails. Decision: no marker.

Pre-merge gate (all must hold at merge time, on the rebased branch): AC1 (headroom), AC2 (no `ZIREF` or `IREF` line touched), AC8 (parity green on the trial merge, diff scope) and AC9 (the CI job `inngest-userdata-budget` is green and its log line is quoted in the PR body next to the offline figure).

Post-merge read, agent-run, no host contact: the push-apply run for the merge sha concludes success, its log has no `hcloud_server.inngest` in plan or refresh, and the plan is 0 changes (`gh run list --workflow apply-web-platform-infra.yml --commit <merge-sha>` then `gh run view <id> --log`, grep for the address). Better Stack check for "nothing was replaced" (AC12): no `provision-unit-armed` row with a new `iid=` for `host=soleur-inngest` after the merge time, with the query window starting before the merge and a liveness control query in the PR evidence. No Doppler, Hetzner or SSH read.

Flip conditions (switch to the marker, as a branch-commit body line, and re-ask): the trial-merge plan of the push path lists `hcloud_server.inngest`; parity is red; a `ZIREF` or `IREF` line changed; a push apply in the previous 24 hours had a non-zero outcome on an Inngest-referencing resource. If the post-merge read shows anything other than 0 changes: stop, file an `action-required` issue naming the action, do not retry and do not dispatch.

Web-redeploy notice for the PR body (the convention of #9755 item 3, notice plus a post-merge apply-outcome check; the wording below is the PR-1 prework plan's): "Merging a change under `apps/web-platform/infra/**` fires the production apply of the parent root and may redeploy the web platform. This change touches user_data of the Inngest host and plans no web-platform resource change; the apply outcome is verified after merge (apply run conclusion, Better Stack via `scripts/betterstack-query.sh`, no SSH)." Also in the PR body: merging causes no user impact and does not touch the Inngest host; the PR-time infra plan will show the host as replaced and that is known drift; Better Stack alert definitions outside the repo were not readable (R1 dissent); the host replace, the resume and the flip need their own typed goes.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing at merge (the host is not touched); a trim that broke the cloud-config or a host script would surface at the next authorized replace as the sole Inngest scheduler failing to boot or provision, so scheduled reminders, crons and agent runs stop firing until the host is repaired. The pre-merge suites, the cloud-init schema validation and the rendered-script execution tiers are what stand between a bad trim and that replace.
- **If this leaks, the user's workflow is exposed via:** no new vector; the edit removes text and moves prose into comments that the render strips, and it adds no secret, token or endpoint. The moved prose contains no credential.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** matches the PR-1 prework plan's tier: code-only text removal that reaches no live host and the failure that matters lands at the owner-gated replace on the shared scheduler (many users), not on one user; a single-user tier would be argued only because the host is a sole copy, which this change does not alter.

## Observability

```yaml
liveness_signal:
  what: the Better Stack heartbeat betteruptime_heartbeat.inngest_prd (host liveness, unchanged by this PR) plus the CI job inngest-userdata-budget printing stored bytes and headroom on every infra PR and every push to main
  cadence: heartbeat per its configured period; the CI job per infra PR and per push to main
  alert_target: operator email through the "Infra Validation failed on main" notify step when inngest-userdata-budget fails on a push; the Better Stack heartbeat policy for host liveness
  configured_in: .github/workflows/infra-validation.yml (job inngest-userdata-budget and the notify-main-failure step) and apps/web-platform/infra/inngest-userdata-budget.sh

error_reporting:
  destination: the CI job log and the main-failure email for size and render faults; host boot faults keep reaching Better Stack through inngest-boot-phone-home.sh with the same markers
  fail_loud: "inngest-userdata-budget: OVER CAP by N bytes" with exit 1, "RENDER FAILED" with exit 2, and the apply run turning red on a HALT

failure_modes:
  - mode: the trim leaves the template unrenderable or the cloud-config invalid
    detection: the workflow run log of the infra-validation jobs - the budget script exits 2 (RENDER FAILED) and the validate job's cloud-init schema check fails on the PR
    alert_route: red infra-validation checks on the PR, email on a red push to main
  - mode: headroom regresses below the floor after a rebase or a concurrent edit to the file
    detection: AC1's jq gate fails on the branch and the budget script prints the new headroom in the workflow run log (::error:: on over-cap)
    alert_route: the PR cannot be marked ready; a later push to main that goes over the cap exits 1 and emails ops
  - mode: a trimmed host script or unit misbehaves on a future replace
    detection: the provision-unit suite (rendered-script execution and the systemd container tier) and the boot-emitter suite before merge; after a later authorized replace the Better Stack rows (journald source via the vector Source 4 allowlist, SYSLOG_IDENTIFIER-isolated) for provision-unit-armed and bootstrap-done on the new host
    alert_route: red suites on the PR; Better Stack boot-trace rows and the existing heartbeat-miss alert for the host
  - mode: the merge apply plans or touches hcloud_server.inngest
    detection: terraform-target-parity pre-merge, then the workflow run log of the push apply read after merge (address absent, 0 changes), and no new provision-unit-armed row for a new iid in Better Stack
    alert_route: the destroy-guard HALT turns the apply run red and emails ops; an action-required issue is filed by the post-merge read

logs:
  where: GitHub Actions run logs (infra-validation inngest-userdata-budget, apply-web-platform-infra push run); Better Stack source soleur-inngest-vector-prd for the host's journal and boot-trace rows
  retention: GitHub Actions default of 90 days; Better Stack 90 days on the paid plan (measured value recorded in knowledge-base/engineering/operations/runbooks/betterstack-log-query.md)

discoverability_test:
  command: bash apps/web-platform/infra/inngest-userdata-budget.sh --json
  expected_output: headroom
  credentials_required: "terraform binary, not a credential - the templatefile() and base64gzip() render has no allowlisted unauthenticated substitute and the terraform binary is absent from preflight Check 10's sandbox PATH, so Check 10 records SKIP-DECLARED; the real gate is the CI job inngest-userdata-budget and AC1 run locally"
```

## Infrastructure (IaC)

### Terraform changes

None. No `.tf` file changes; `inngest-host.tf`, its strip regex and the `lifecycle.precondition` on `hcloud_server.inngest` are untouched. No new variable, secret or provider.

### Apply path

(a) cloud-init-only edit of a template that is already rendered for an existing host: it reaches a host only through the next separately authorized `inngest-host-replace` dispatch (own typed go, out of scope). No in-place edit, no SSH, no dispatch from this work. Expected downtime and blast radius of this PR: none; merging fires the parent-root push apply with an expected 0 changes.

### Host fan-out

No `terraform_data` SSH provisioner under `apps/web-platform/infra/` is edited. The only `terraform_data` that reads this file is the zot consumer probe, through the `ZIREF` line, which stays byte-identical. Fleet siblings (web-1, web-2, git-data, registry) are unaffected.

### Distinctness / drift safeguards

`hcloud_server.inngest` keeps no `ignore_changes` on `user_data` (ADR-100), so the unscoped drift plan keeps showing a replace until the owner-gated replace happens (already the case before this PR). The size precondition and the budget script stay as the guard. No state storage change.

### Vendor-tier reality check

Not applicable: no vendor resource is created. The one vendor limit that matters is Hetzner's 32,768 B `user_data` cap, measured by the script.

## Encryption Posture

This PR introduces no persistent store and no new connection (a template trim). The file name matches the posture gate's `cloud-init.*\.ya?ml$` detection, so the one store whose apparatus this template carries is declared below as UNCHANGED; the authority for every field is its entry in `scripts/encryption-posture-ledger.json` (store `hcloud_volume.inngest_redis_luks`), and `python3 scripts/lint-encryption-posture.py --repo-sweep` re-resolves the template's anchors in the verification list.

```yaml
at_rest:
  - store: hcloud_volume.inngest_redis_luks (unchanged; this PR edits none of its resources)
    mechanism: luks
    evidence: the template's `cryptsetup luksFormat` and `cryptsetup luksOpen --key-file - "$DEV" inngest-redis` anchors in cloud-init-inngest.yml stay byte-identical (the LUKS first-boot stage is not touched, P1); ledger entry above
    defends_against: a seized, RMA'd or snapshot-imaged Hetzner block volume carrying the Inngest queue and run-state AOF
    does_not_defend: a leaked credential; an app-layer read on the unlocked host; a compromised redis or inngest process; and the sole-copy risk (the volume is the only copy of the store and the Doppler key the only copy the host reads)
    disclosed_as: not-publicly-claimed
    live_verification: "unavailable: per the ledger entry the hourly server probe proves which device backs /mnt/data, not the cipher; unchanged by this PR"
in_transit:
  - connection: none added; the existing web-to-Inngest private-network edge and the TLS terminator units are untouched
    tls: unchanged (per the ledger connection entries)
    cert_verification: unchanged
    does_not_defend: a passive on-net attacker on the private network for the plain-HTTP edge, as recorded in the ledger connection entry
    disclosed_as: per the ledger connection entry
```

## Guard Contract

### Guard 1 - Guard 3 stem scan covers cloud-init-inngest.yml

**Property.** No non-comment line of `cloud-init-inngest.yml` names the retired cutover trio (`inngest-luks-cutover`, `inngest_luks_cutover`, `INNGEST_LUKS_CUTOVER_SH`), so the template can never again stage, quiesce or poll units the image no longer carries.

**Assembly.** One scan function `scan_file` called from `g3_scan` over `RECIPE_FILES` and `DELIVERY_FILES` in `inngest-carrier-vocabulary.test.sh`; adding the template to `DELIVERY_FILES` makes the real-tree scan, the fixture copy (`make_tree` copies every `DELIVERY_FILES` entry), the generated `trio-<basename>` row and the generated unreadable-file handling cover it. Members drift; the chokepoint is the single `scan_file` stem match after `strip_comments`, which also covers any later added delivery file. The template's identity-regex names (`LUKS_CUTOVER`, `LUKS_ACTIVE_VOLUME_ID`) are live secret names and do not match the stems.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Run the scan against the UNMODIFIED template (the failing-test-first row): 6 stem hits | RED (`trio-named`) |
| 2 | Append the bare stem as code (`X=inngest-luks-cutover`) to the template fixture copy | RED (`trio-named`) |
| 3 | Re-add the three names to the `STAGED=` line | RED (`trio-named`) |
| 4 | Re-add `inngest-luks-cutover.timer` to the quiesce `for _t in` loop, after a compliant first member (`inngest-cutover-flip.timer`) | RED (`trio-named`) |
| 5 | Brace form `inngest-luks-cutover.{sh,service,timer}` in a code line | RED (`trio-named`) |
| 6 | Snake-case `inngest_luks_cutover` field and upper-case `INNGEST_LUKS_CUTOVER_SH` in the template | RED (`trio-named`) |
| 7 | Remove the template file from the fixture tree (the guard's own dispatch: unreadable is a violation, never a skip) | RED (`unreadable`) |

Harness rows: the suite's existing negative controls (`neg-noop`, `neg-wrong-tag`, `neg-green-noop`, `neg-green-overblock`) already judge the verdict helpers and need no new row; the per-file `trio-<basename>` row is generated from `DELIVERY_FILES`, so dropping the template from the array removes its row and row 1 (the real tree against the unmodified template) is the positive control that the scan reads the file. Must-PASS rows (non-canonical, permitted by the contract): a whole-line `#` comment naming the retired trio in the template stays GREEN (history prose is legal), and a code line whose trailing text is a comment that names the trio is RED (comment stripping must not eat code). Anchor: the stored values here are the `NEEDLES_PINNED` literal and `CARRIER_FLOOR`; this PR changes neither, and the scan judges the SOURCE tree, so the anchor that a weakening PR also has to move is the test file itself, reviewed in the same diff.

Post-change survivor check (the mutation that defeats the mechanism after the remediation lands): the remediation deletes text and writes only `#` comments, so the first question is whether the new comment text matches the classifier; it does not, because the scan strips whole-line comments before matching, and the moved prose names none of the stems.

### Quiesce battery adaptation (not a new guard)

`cloud-init-inngest-provision-unit.test.sh` pins the quiesce loop with rows that name the retired trio (T4, Q2, Q3, Q5, the `Q_OPEN` constant and the G2-r14 mutation row). Change A removes their inputs, so the rows are re-pointed or dropped: T4 on the flip timer, Q2 and Q3 and the `luks-cutover` fixture state dropped, Q1, Q4 and Q5 kept (Q5 with the flip flag only), `Q_OPEN` and G2-r14 re-pointed to the new loop text (G2-r14 now empties the busy-check loop), G2-r12 and G2-r15 unchanged. No mutation rows are added. The exact executed-row counts come from a run of the suite, never from the header.

## Open Code-Review Overlap

One open code-review issue names a planned file: #10243 (nft comment correction on PR 8945, in `cloud-init-inngest.yml`). Disposition: acknowledge. It is a comment-only correction (0 B after the strip) in the nftables script region this PR does not otherwise touch; folding it in widens review for no byte benefit, and it stays open. No open code-review issue names the two test files.

Related open work: #11140 (leftovers from the trio retirement) item 7 is the STAGED list and quiesce loop, which this PR delivers; the PR body says `Ref #11140` (item 7 done; the `--min-headroom` floor is added there as a tracked deferral, see Acceptance Criteria) and `Closes #11080`.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Land #11080 as its own PR: trim apps/web-platform/infra/cloud-init-inngest.yml user_data by at least 500 B" [brief] | Proposed Solution step 3 (A, B, C) | mapped |
| 2 | "so the CI-rendered margin on a trial merge of current main reaches at least 300 B" [brief] | AC1 (headroom >= 780 B offline, equal to the CI render) and the pre-merge gate item 4 | mapped |
| 3 | "this PR must NOT replace or dispatch anything on the Inngest host" [brief] | Merge safety; AC8 (diff scope); no dispatch step anywhere | mapped |
| 4 | "check how the per-merge push apply treats it (the server_touched abort in apply-web-platform-infra.yml and the [skip-web-platform-apply] merge-commit marker) and make the merge safe before merging" [brief] | Merge safety (R2), Research Reconciliation row 3 | mapped |
| 5 | "Do not dispatch inngest-host-replace, the resume, or the flip" [brief] | Overview hard constraints; O2 in the decision table | mapped |
| 6 | "Read ruling T4 ... and issue #11080 first." [brief] | Research Insights, Premise Validation | mapped |
| 7 | "prove behavior-neutrality with the existing suites (cloud-init-inngest-bootstrap.test.sh etc.)" [brief] | Test surface, AC4 and AC5 | mapped |
| 8 | "Production evidence only through Better Stack." [brief] | Merge safety post-merge read; R4 | mapped |
| 9 | "Persist every decision as a row of the `\| Item \| Class \| Ruling \|` table in knowledge-base/project/specs/<branch>/decision-challenges.md" [brief] | `decision-challenges.md` beside this plan | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| A: drop dead trio references | "comments, duplicated blocks, content that could move into the image or the render-stripped prose region" | asked |
| B: shorten five Descriptions | "trim apps/web-platform/infra/cloud-init-inngest.yml user_data by at least 500 B" | asked |
| C: move log-message prose into stripped comments | "content that could move into the image or the render-stripped prose region" | asked |
| Guard 3 extension to the template | - | inferred - justification: ruled by the CTO (R3); without it change A regresses silently, and the test header already promises it |
| Quiesce battery adaptation | "prove behavior-neutrality with the existing suites" | asked |
| Runbook table sync | - | inferred - justification: the removed tails are the only readable home of operator-facing diagnosis (curl rc map, token-file-empty consequence); the runbook must carry it once the render drops the prose |
| Tracking issue for the deferred `--min-headroom` floor | - | inferred - justification: `wg-when-deferring-a-capability-create-a` and ruling R3 |

### Split Assessment

- Subsystems touched: 1 - `apps/web-platform/infra` (template, two test files) plus one runbook row
- Planned files: 4 edited (template, two tests, runbook) | Estimated changed lines: about 140
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Files to Edit

- `apps/web-platform/infra/cloud-init-inngest.yml` (A1, A2, A3, B x5, C x4)
- `apps/web-platform/infra/inngest-carrier-vocabulary.test.sh` (Guard 1)
- `apps/web-platform/infra/cloud-init-inngest-provision-unit.test.sh` (quiesce battery adaptation)
- `knowledge-base/engineering/operations/runbooks/inngest-server.md` (marker rows, unconditional: the cut tails are the only place this diagnosis lives today)

## Files to Create

None in the product tree. Planning artifacts only: this plan, `knowledge-base/project/specs/feat-one-shot-11080-inngest-userdata-trim/tasks.md` and `decision-challenges.md`.

## Implementation Phases

### Phase 0 - Preflight (no edits)

- 0.1 Rebase onto `origin/main` (never merge main in). Re-run `bash apps/web-platform/infra/inngest-userdata-budget.sh --json` and record the baseline; if main moved, re-measure the candidate set in a scratch copy before editing.
- 0.2 `git diff origin/main --stat` is empty for the template; confirm the `ZIREF` and `IREF` lines and the `| grep -q` count (4) before editing.
- 0.3 Re-grep the five Description strings and the four message tails across `*.test.*`, `scripts/` and `.github/` for new pins since this plan.
- 0.4 Add the deferred `--min-headroom 300` floor as a new item on #11140 (a comment, `Ref` both ways) before the PR is marked ready.

### Phase 1 - Red tests first

- 1.1 Guard 1 rows in `inngest-carrier-vocabulary.test.sh`; run it: the real-tree row is RED (6 stem hits).
- 1.2 Quiesce battery adaptation in the provision-unit suite is prepared but its green state depends on Phase 2, so run only the rows that exist today and keep the old battery until the template changes in the same commit; record that the old rows still pass against the unmodified template (control).

### Phase 2 - Template edits

- 2.1 A1, A2, A3, then measure; 2.2 B, then measure; 2.3 C, then measure. Record the headroom after each step in the PR body (expected 428 B, 528 B, 800 B).
- 2.4 If the final figure is below 780 B after the rebase, re-measure first (a moved baseline is the likely cause). Blank-line removal in the template (about 90 B, ruled as the fallback in R1) closes a shortfall of up to about 90 B only. If C has to be reverted for an alert-match reason, the floor is NOT reachable in this PR: A + B(5) measures 528 B and adding blank-line removal gives about 618 B, below 780 B. In that case stop, record it, and re-ask the CTO (ruling note P4); do not ship below the floor and do not present blank-line removal as sufficient.

### Phase 3 - Verification (one suite at a time, stdin from `/dev/null`, long ones in the background with a completion wait)

Run in this order: `inngest-carrier-vocabulary.test.sh`, `inngest-host.test.sh`, `inngest-boot-emitter.test.sh`, `cloud-init-inngest-bootstrap.test.sh`, `inngest-redis-luks.test.sh`, `inngest-redis-luks-loopback.test.sh` (needs root and a loop device; if the environment lacks them record that and rely on `inngest-redis-luks.test.sh`), `journald-config.test.sh`, `inngest-config-refresh.test.sh`, `templatefile-bare-dollar-guard.test.sh`, `credential-persist-home-guard.test.sh`, `doppler-injection-bound.test.sh`, `cloud-init-ghcr-seed-login.test.sh`, `cloud-init-web-zot-seed.test.sh`, `web-zot-consumer-probe.test.sh`, `inngest-nic-wait.test.sh`, `inngest-cutover-flip.test.sh`, `inngest-server-flip-guard.test.sh`, `inngest-provision-rehearsal.test.sh` (renders the same template in the rehearsal root), `cloud-init-inngest-zot-pull-mutation.test.sh` (about 227 s), `cloud-init-inngest-provision-unit.test.sh` (about 4 min), then the required-CI set: `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts`, `bun test plugins/soleur/test/terraform-target-parity.test.ts`, `bash .claude/hooks/grep-q-pipe-guard.test.sh`, `python3 scripts/lint-encryption-posture.py --repo-sweep`, `bash tests/scripts/test-argv-bearer-sweep.sh`, and `bash .github/scripts/validate-infra-templates.sh apps/web-platform/infra` (the cloud-init schema check; needs `cloud-init` locally, otherwise rely on the CI `validate` job). A baseline of the slow provision-unit suite on unmodified main is recorded here: 88/88 rows (RED 79/79, must-PASS 9/9), Tier B ran.

### Phase 4 - Ship

PR body carries: the baseline and per-step headroom, the CI log line of the budget job, the web-redeploy notice, the statements listed in "Merge safety", `Closes #11080` and `Ref #11140`, `Ref #10390`, `Ref #10112`, `Ref #10975`, and the owner-go sentence. Mark ready only with the pre-merge gate satisfied; the merge itself needs the owner's typed go (O1). After merge the post-merge read runs and is attached to the PR; it never touches the host.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `bash apps/web-platform/infra/inngest-userdata-budget.sh --json | jq -e '.headroom >= 780 and .stored_bytes <= 31988'` exits 0 on the branch rebased onto current `origin/main` (script: `inngest-userdata-budget.sh`, gate ruled in R1).
- [ ] AC2: `git diff origin/main -- apps/web-platform/infra/cloud-init-inngest.yml | grep -E '^[+-].*(ZIREF|IREF)='` prints nothing (exit 1); the web-probe hash line is untouched.
- [ ] AC3: `grep -vE '^[[:space:]]*#' apps/web-platform/infra/cloud-init-inngest.yml | grep -cE 'inngest-luks-cutover|inngest_luks_cutover|INNGEST_LUKS_CUTOVER_SH'` prints `0` (it prints 6 on main), and `bash apps/web-platform/infra/inngest-carrier-vocabulary.test.sh` is green with the template in `DELIVERY_FILES` (Guard 1, rows listed above).
- [ ] AC4: every suite in the Phase 3 list passes, run one at a time with stdin from `/dev/null`; the provision-unit suite prints `PROVISION_UNIT_SUITE_OK` with row counts equal to the executed counts recorded in its header (not 88/79 from a remembered literal).
- [ ] AC5: the four required-CI checks pass locally: `cloud-init-user-data-size.test.ts`, `terraform-target-parity.test.ts`, `grep-q-pipe-guard.test.sh` (census row for the template still `= 4`) and `lint-encryption-posture.py --repo-sweep`; `test-argv-bearer-sweep.sh` also passes.
- [ ] AC6: the markers survive verbatim: `grep -c 'SOLEUR_INNGEST_BOOT_TRACE_LOST' apps/web-platform/infra/cloud-init-inngest.yml` and `grep -c 'SOLEUR_INNGEST_BS_TOKEN_RESTAGE_FAILED' apps/web-platform/infra/cloud-init-inngest.yml` each print the same count as on main, and `grep -E 'logger -t inngest-(boot-phone-home|bs-token-restage) "SOLEUR_INNGEST_(BOOT_TRACE_LOST|BS_TOKEN_RESTAGE_FAILED)' apps/web-platform/infra/cloud-init-inngest.yml | grep -vc '#7228'` prints 0.
- [ ] AC7: the moved prose lives in whole-line `#` comments and no `${` or `%{` sequence was introduced in them: `git diff origin/main -- apps/web-platform/infra/cloud-init-inngest.yml | grep -E '^\+[[:space:]]*#' | grep -cE '\$\{|%\{'` prints 0; `templatefile-bare-dollar-guard.test.sh` passes.
- [ ] AC8: `git diff origin/main --name-only` lists only the files in "Files to Edit" plus the planning artifacts and the archived-plan moves the pipeline makes (diff-scope AC: none of `inngest-host.tf`, `infra-config-install.sh`, `cosign-trusted-root.json`, `server.tf`, `hooks.json.tmpl` or any `.github/workflows/*` file appears), and `terraform-target-parity.test.ts` is green on the trial merge.
- [ ] AC9: the CI job `inngest-userdata-budget` is green on the PR, and the PR body quotes both the offline figures and that job's log line; the PR body contains the web-redeploy notice, the statement that the PR-time plan shows the host as replaced as known drift, the Better Stack alert-definitions gap, and no claim that the host was probed.
- [ ] AC10a: the runbook carries the moved diagnosis: `grep -c 'BS_TOKEN_RESTAGE_FAILED' knowledge-base/engineering/operations/runbooks/inngest-server.md` prints at least 1 (it prints 0 on main), and the same file contains the strings `token-file-missing`, `token-file-empty`, `post-failed` and the curl rc map `6/7`.
- [ ] AC10: the deferral of the `--min-headroom 300` floor has a tracking issue (item in #11140 or a new issue) referenced in the PR body, filed before the PR is marked ready.

### Post-merge (automated read, no host contact)

- [ ] AC11: the push-apply run for the merge sha concludes `success`, its log has no `hcloud_server.inngest` in plan or refresh, and the plan reads 0 changes; the run URL is attached to the PR.
- [ ] AC12 (corroboration only; AC11's apply log is the authoritative proof): `scripts/betterstack-query.sh --since <a time before the merge> --grep provision-unit-armed` and `--grep inngest-bs-token-restage` (the runbook's double `fromjson?` decode, isolated on `.host == "soleur-inngest"`) show no `provision-unit-armed` row carrying a new `iid=` after the merge time (a plain reboot emits a RESTAGED row but keeps the `iid`, so only a new `iid` means a replace), and a liveness control (`--grep inngest- --limit 20`) shows rows after the merge; the hot window is short, the query includes the archive arm. If AC11 or AC12 fails, an `action-required` issue is filed and nothing is dispatched or retried.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO rulings R1 to R4 (2026-10-26) are recorded in `decision-challenges.md`: ship A + B(5) + C and reject the wider strip; no marker with a pre-merge gate and a post-merge apply-run read; extend Guard 3 to the template and defer the headroom floor to PR-D; no live-host read. Other domains: no user-facing surface (Product none), no regulated-data surface (the GDPR gate does not fire; no schema, auth, API or personal-data path), no spend or vendor change, no marketing or legal content.

## Test Scenarios

1. Given the unmodified template, when the extended Guard 3 runs, then it reports `trio-named` for `cloud-init-inngest.yml` (failing test first).
2. Given the trimmed template, when the budget script runs, then stored bytes are at most 31,988 and headroom at least 780.
3. Given a fixture where the quiesce loop names a unit that never activates, when the provision script runs, then it proceeds to the bootstrap; given the flip service `activating` past the bound, then it exits 1 with `provision-fsm-busy` and restarts the flip timer only.
4. Given a failed bootstrap attempt with the flip timer active beforehand, then exactly that timer is started again (T4 adapted).
5. Given the rendered phone-home and restage scripts, when each failure path is driven, then the journal line still carries the marker, `stage`, `reason`, `rc` or `drc` and `#7228`.
6. Given the rendered cloud-config, when `cloud-init schema` validates it, then it is valid.

## Dependencies & Risks

- **Thin margin over the floor (800 B against 780 B).** Mitigated by re-measuring after the rebase and by the ruled fallback for a small shortfall (blank lines, about 90 B). The fallback cannot replace C: reverting C leaves the PR about 160 B short of the floor, which means stop and re-ask (P4). A concurrent edit to the file (bot pin bumps change only the 64-hex digest, same length) cannot move the figure materially.
- **Better Stack alert definitions outside the repo were not readable.** Mitigated by keeping every marker, field and `#7228` verbatim; the R1 flip reverts only C if an alert keys on tail text.
- **Fixture counts in the provision-unit suite are exact.** Mitigated by taking executed counts from a run; the header currently says 83 rows while the suite reports 88.
- **Pinned text elsewhere.** Mitigated by Phase 0.3 re-grep and by running the full Phase 3 list (the affected-tests map has no entry for the template).
- **Merge applies in production.** Mitigated by the pre-merge gate and post-merge read; expected 0 changes; no host contact.
- **Ordering with later work.** The keeper trio (PR-2), the `LUKS_HDR_PUT` admission and the `fetch_rc=93` fix all edit this file and need the margin this PR creates; they merge after it.

## Sharp Edges

- A plan whose `## User-Brand Impact` is empty or carries only placeholder text fails `deepen-plan` Phase 4.6; this one is filled.
- Comment-only edits gain 0 B because the strip removes whole `#` lines; every figure in this plan is a measured stored-size delta, never a character count (the template has non-ASCII em dashes; terraform `length()` counts graphemes).
- Moving prose into a comment inside a `content: |` shell body is safe only because the strip runs on the rendered document; do not put `${` or `%{` in it (templatefile evaluates comments).
- The `ZIREF` and `IREF` lines are read by `web-probe.tf` and rewritten by the pin-bump bot; never reflow them.
- Do not trim the first-boot LUKS pointer or unpointed arms: which one is live depends on a Doppler value this work may not read.
- A marker line, if the R2 flip ever applies, must be its own line in a BRANCH COMMIT BODY (squash uses `COMMIT_MESSAGES`); a subject-line marker does not survive.

## References

- Issue #11080; ruling T4 in `knowledge-base/project/specs/archive/20261025-190820-feat-one-shot-terminator-journald-shipping/decision-challenges.md`; #11140 item 7; PR #10966 (trio retirement) and its plan `knowledge-base/project/plans/archive/20261025-173406-2026-10-24-feat-inngest-host-replace-window-prework-plan.md` (PR-D byte plan); #10975 (terminator journal); ADR-100, ADR-152, ADR-185.
- Files: `apps/web-platform/infra/{cloud-init-inngest.yml,inngest-host.tf,inngest-userdata-budget.sh,inngest-carrier-vocabulary.test.sh,cloud-init-inngest-provision-unit.test.sh,web-probe.tf}`, `.github/workflows/{apply-web-platform-infra.yml,infra-validation.yml,mint-inngest-bootstrap-tag.yml}`, `plugins/soleur/test/{cloud-init-user-data-size,terraform-target-parity}.test.ts`.
