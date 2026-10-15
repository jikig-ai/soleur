---
title: "feat: build the git-data wipe body (mode=wipe / wipe_finish / wipe_check)"
date: 2026-10-14
slug: git-data-wipe-body
branch: feat-one-shot-10138-git-data-wipe-body
issue: 10138
closes: none (Ref #10138, Ref #6897; the wipe itself stays owner-gated)
type: feat
priority: p1
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# feat: build the git-data wipe body (`mode=wipe` / `wipe_finish` / `wipe_check`)

## Enhancement Summary

**Deepened on:** 2026-10-14
**Sections enhanced:** Reconciliation, Research Insights, Implementation Phases (rewritten after review), Guard Contract (8 guards), Observability, Acceptance Criteria.
**Evidence used:** six-seat plan-review panel (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow-analyzer, CTO devex), two CTO ruling batches (25 rows), CLO and CPO assessments, a learnings sweep, a repo reconciliation sweep, and live read-only measurements (Hetzner API, Better Stack).

### Key improvements
1. The design's S3 re-entry arm had dead ends (detach unconfirmed, volume already absent, no store-serving proof, 24 h bound); replaced by a typed `origin_run`, Hetzner action-history evidence and an absent-volume branch.
2. Token containment tightened: every post-loader step is `exec env -i`, the false-assurance blanking step is gone, the Doppler CLI install in the job is pinned and the job has no remote `uses:`.
3. The emptiness signal was decided from a measurement (`plaintext_journal=dirty`), reports counts only, and the two rulings that touch it (CTO and CLO) are reconciled explicitly.
4. A read-only `wipe_check` mode lets the owner exercise W1-W7 under real credentials before naming a destructive command.

### New considerations discovered
- The design's ids are already stale: a sibling apply replaced the git-data host on 2026-10-14 (new server and LUKS volume ids); nothing may be a constant.
- The retired `wipe` job of `workspaces-luks-cutover.yml` (git history) is a direct precedent for the API sequence and also shows the `assert_apply_paused_idle` alternative for the wedge.
- Draft PR #10185 shares the argv-bearer sweep floor literals (merge-conflict hot spot, recorded in Risks).

### Deepen-plan verification (2026-10-14)
- Gates 4.6 (user-brand impact), 4.7 (observability: `expected_output` is a single literal, command offline and fast), 4.8 (no PAT-shaped variable), 4.9 (no UI surface), 4.10 (encryption posture), 4.11 (`lint-guard-contract.py`: 8 guards green) and 4.12 (one unfenced Scope Check, no block marker) pass.
- Every `#N` cited was resolved live (`gh issue view` / `gh pr view`); every cited rule id exists in `AGENTS.md`.
- Live read-only check of the Hetzner action-history shape `wipe_finish` relies on: `GET /volumes/<plaintext id>/actions` returns objects with keys `command`, `finished`, `id`, `progress`, `resources`, `started`, `status`; `command` values seen are `attach_volume`, `create_volume`, `detach_volume`; every status seen is `success` (22 actions). The detach POST (201) and DELETE (204) shapes stay pinned from the retired job and are first exercised live by the destructive run's fail-closed reads.

## Overview

Issue #10138 is the owner decision issue for DL-2: ending the retention of the plaintext rollback copy
`hcloud_volume.git_data` (Hetzner volume named `soleur-git-data-store`). The wipe body does not exist on
`main`. This plan builds the BODY only: a new `wipe` job in `.github/workflows/git-data-cutover.yml` with three
dispatch modes (`wipe`, `wipe_finish`, `wipe_check`), the helper and host verb it needs, its census tests, the
runbook section and an ADR-241 amendment note. It builds from the merged design
`knowledge-base/project/specs/archive/20261013-002507-feat-one-shot-git-data-luks-cutover-8211/design-wipe-body-pr.md`
(read in full, with `decision-challenges.md`, `design-rollback-rehearsal.md` and `design-9943-liveness-precheck.md`
where the wipe design cross-references them).

**What this PR does not do (hard constraints, restated so the work phase cannot drift):** it never runs the wipe,
never dispatches any workflow, applies nothing, writes nothing to production, edits no legal document (the CLO
re-ruling is due 2026-10-24, #9066; legal wording is #8551/#10136), does not edit `AGENTS.rules.md` (ADR-092) and
never uses the headless `pending_deployments` approval form for any wipe mode. The owner names every dispatch.

**What the plan settles from the design's open items** (rulings are rows in
`knowledge-base/project/specs/feat-one-shot-10138-git-data-wipe-body/decision-challenges.md`): V-4, V-8, V-9, V-13/N-19
(measured, below), V-14 and the ADR-241 amendment note, plus fourteen build forks and eleven plan-review forks put to the
CTO and wording rulings from the CLO. **Plan-review round 1 (six seats) changed the design in these ways**, all recorded
as rows: `wipe_finish` takes a typed `origin_run` input and Hetzner action-history evidence instead of a run-list scan and a
24 h bound, and has an absent-volume branch; W11b and the verdict-record binding triple are dropped; every post-loader step
is `exec env -i`; the Doppler CLI install in `wipe` is pinned; the listing reports counts only (no digest); the epoch bound
moves (W10b re-stamp, 60 s delete bound); the legacy-title classifier is cut; the build is layered so the read-only front
can ship alone.

## Research Reconciliation: Spec vs. Codebase

The design says its figures are claims to re-read. Re-read on 2026-10-14 (HEAD `e6ba694846`, read-only):

| Design / ADR claim | Reality now | Plan response |
|---|---|---|
| Plaintext volume 106867358, LUKS volume 107102614, server 169724272 (ADR-239, 2026-10-12) | Hetzner API (read-only token): server `soleur-git-data` is id 170368003 created 2026-10-14T14:33:56Z; LUKS volume `soleur-git-data-luks-store` is 107125716; plaintext volume 106867358 is attached to the new server, `protection.delete=false`, label `app=soleur-web-platform`, location hel1. A sibling apply replaced the host today. | Ids are NEVER constants in code or tests. The helper reads names (`?name=`), W4 binds the record to what the API returns, and `wipe_check` shows the owner the live pair before any destructive dispatch. |
| `workflow` is 56.8 KB | 60,024 bytes; cap `WORKFLOW_FILE_GATE_BYTES = 490_000` (`plugins/soleur/test/workflow-file-size.test.ts`, ADR-231) | Budget is not binding (about 430 KB headroom); still run the size test. |
| The `plaintext_empty=yes` row is at least 7 days old when read | The newest `boot_complete` for `soleur-git-data` is 2026-10-14T14:34:43Z (today's replace), `plaintext_volume=present plaintext_empty=yes served_repos=0 plaintext_journal=dirty`; older rows 2026-10-11 and 2026-10-08 carry the same values. | W5 requires the row to belong to the CURRENT server (`dt >= created`), not an age. After a flip no newer row can exist (design 3.2); the age rule is not coded, so a fresh row is simply fine. |
| `plaintext_journal` state of the live volume unknown | `dirty` in all three newest rows (query in Research Insights) | CTO's gate: option D (`debugfs`) does not apply; the build ports the bootstrap's dm-snapshot unit into the W7 host verb (option A). |
| `d6_replace_stale` text steers the owner to dispatch the rotate (#10166, #10175 "OPEN") | #10166 and #10175 are CLOSED (PRs #10184, #10207 merged). The `d6_replace_stale` message already names the `store_dirty` refusal and the runbook section "When a rotate is needed after the flip". | No workflow code change for the message; the runbook wipe section cross-references it. Precondition 2 of the design is met by repo state. |
| Design precedent for the Hetzner lookup is `workspaces-luks-cutover.yml` | That workflow falls back from `HCLOUD_TOKEN_READONLY` to the read/write `HCLOUD_TOKEN`. The wipe must never fall back. A retired `wipe` job with a detach/poll/DELETE/404 sequence exists in git history (`git show 3ed3e4e6da^:.github/workflows/workspaces-luks-cutover.yml`, job `wipe`, step "Detach and delete the plaintext volume (Hetzner API)"). | Reuse its API sequence (POST detach 201, poll the SAME action, never re-POST; DELETE 204; 404 counts as gone only with a presence proof that the LUKS volume is still attached). Never reuse the fallback. |
| Gate counters: "S5 order and mask populations" (brief) | `test-argv-bearer-sweep.sh` S3 holds workflow steps (file-level manifest, `S3_CALLS_FLOOR=41`, `git-data-cutover.yml` already listed); S4 holds script consumers of `scripts/lib/bearer-curl.sh` (`S4_POP_FLOOR=21`, `S4_SCALLS_FLOOR=4`); S5 is `apply-web-platform-infra.yml` only. | The Hetzner calls live in a helper script (CTO ruling), so the helper joins the S4 population; any inline `bc_curl` in a `wipe` step joins S3 and raises its floor. No `2>/dev/null` on a `bc_curl` call (it would hide the refusal marker). |
| G2 mutating-verb census, G5 "exactly five `gd_capture` sites", `AC9` local-action set `[bridge, notify]`, `WF-jobs`, `WF-timeout`, `N-if`, `EXPR_OK`, `D-6` order pin | All exist as the design says (the order pin is a 17-selector subsequence of the `cutover` job, not the full step list). | Each moves deliberately in Phase 5 (re-pinned to exact new values, never loosened). |
| `liveness_precheck` (#9943), `run-name`, `volume_id`, `FLAG_MODE=wipe`, the stamp read, `RUNG2_PLAINTEXT_VOLUME` | None exist (#9943 is open and unbuilt). `RUNG2_PLAINTEXT_VOLUME` is out of this PR (sibling PR-R, #10296). | The wipe job's order pin does not mention `liveness_precheck`; if #9943 lands first the numbers are re-read at build time. |
| Plan: W5 uses the six-flag pre-bridge deny-list; design says the poll library strips the same set | `_git_data_bs_read` in `scripts/lib/git-data-boot-signal-poll.sh` strips THREE names (`DOPPLER_TOKEN`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`). `git_data_boot_sql` does not select `served_repos`, `plaintext_volume` or `plaintext_journal`; `git_data_boot_complete_freshness` requires strictly greater than the server `created`. | W4/W5 use the library's three-flag form (CTO I; the closed pre-bridge environment is census-pinned). The library gains a field-read query (file added to Files to Edit); freshness reuses the strict function. |
| Design W2: remote Doppler CLI action runs before the loader | `DopplerHQ/cli-action@5351693...` (the step in `cutover`) always runs `cli.doppler.com/install.sh`, i.e. the LATEST CLI, unpinned; the loader pins 3.75.3 with a sha256. | `wipe` pins the install inline (copy of the loader's block) and allows no remote `uses:` at all (CTO B). |
| Design: the retired legacy `cutover` job lets W3 classify legacy rollback runs by step conclusions | The legacy `cutover` job has no rollback-only step (`Write GIT_DATA_STORE_ENABLED` serves flip and rollback). | Classification cut; any legacy-titled run created after the stamp refuses (CTO F). |
| Rollback clears `GIT_DATA_LUKS_CUTOVER_AT` (precondition of the soak floor) | Still false: the only writer is the flip tail step. | #10297 filed. This PR carries the design's interim guard in W3 (stamp newer than the last `mode=rollback` run). |

## Research Insights

### Premise validation (Phase 0.6)

Checked: #10138 (open, the owner decision issue), #6897 (open), #10166 and #10175 and #10137 (closed, merged), #10155
(merged), #8571 (open, a PR-C precondition, not a wipe precondition), #9943 (open, unbuilt), the mechanism against the
ADR corpus (ADR-239 amendments, ADR-241 D1-D9; the mechanism is the one ADR-239 Amendment 2026-10-09 prescribes: the
Hetzner delete is the end event, the volume is never mounted to purge). Stale in the design: the ids and the issue
states above. Collision probe 1 (before planning): `gh pr list --search "10138 in:body" --state all` returned PRs
#10132, #10210, #10271, #10184, all MERGED; no open PR touches `.github/workflows/git-data-cutover.yml`,
`apps/web-platform/infra/git-data-cutover-access.test.sh`, ADR-239 or the runbook (known sibling #10271 is an
evidence-only file and merged).

### Property list (Phase 0.6b)

- P1. A dispatch the owner names and the environment reviewer approves can destroy exactly the plaintext volume
  `soleur-git-data-store`, never the LUKS volume, never a volume whose id the owner mistyped.
- P2. The destroy cannot start unless same-session evidence says: flag true and soaked, Hetzner identity equals the typed
  id, the host shows the device unmounted, not LUKS, unheld, read-only, never written since enumeration, and the volume
  holds nothing a user could lose (boot-time `repositories/` count plus a layout-independent listing).
- P3. Every failure leaves a defined, notified state; an ambiguous state is never read as "nothing changed".
- P4. The Hetzner write token is reachable only by the two steps that need it.
- P5. The owner can exercise the evidence reads read-only before naming the destructive command.
- P6. An interrupted wipe (detached, not deleted) continues only through a typed, gated path.
- P7. After the wipe, no other apply path can plan a git-data host replace from the wedge state.
- P8. Nothing the run prints claims more than "the device was deleted" and nothing prints a name from the volume.

### Cut list (Phase 0.6b)

| Mechanism | Property it would buy | What covers it / why cut |
|---|---|---|
| Terraform plan/apply split for the destroy | P2 same-session | CTO F5: cannot guarantee same-session re-assertion. |
| `resume` input on `mode=wipe` | P6 | `mode=wipe_finish` (it would skip the host assertion). |
| Mounting or purging the volume | P2 | ADR-239 D2 forbids; the delete is the end event. |
| `debugfs`/`e2fsck -n` listing (option D), owner SSH read (B), counters-only (C) | layout signal | dirty journal (measured), `hr-no-ssh-fallback-in-runbooks`, blind to other top-level names. |
| Loader `doppler-token-legacy` input | P4 | V-14: with it omitted only the Tier-B arm can run. |
| Separate success-only summary step (V-4) | P3 | folded into the tail of W12. |
| `pre_detach` phase (V-9a), a "refused before the call" marker (V-8) | P3 | absent phase + `started=='true'` already means "refused before any call". |
| Disabling the push-apply workflows during the wedge (the retired `wipe` job's `assert_apply_paused_idle`) | P7 | gates + the wedge test (design 4); recorded as the alternative if the wedge test cannot be made green. |
| Rung-2 empty-id rehearsal and its gate key | binds PR-C only | moved to #10296 (CTO ruling). |
| W11b token blanking, the verdict-record binding triple, the listing digest, the 30 s W9a-to-W9 bound, the 24 h `wipe_finish` bound, the `wipe_finish_candidate` run-list scan, legacy-title classification | P3 / P4 / P8 | plan-review round 1, CTO A-G: each bought no property the remaining mechanisms do not (`exec env -i` on every post-loader step; epoch + ids; counts; W7 constant in `detach`; Hetzner action history + typed `origin_run`; any legacy-titled run after the stamp refuses). |
| A separate `wipe_check` concurrency group; a single-name carrier for `HCLOUD_TOKEN` | P5 / P4 | rejected / deferred to #10300 (CTO H, J). |

### Measurement: Better Stack archive retention (V-13 / N-19), taken 2026-10-14

All read-only, secrets never printed.

- Command A: `BS_TABLE=t520508_soleur_git_data_prd_logs BS_TABLE_S3=t520508_soleur_git_data_prd_s3 doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh "SELECT min(dt) AS oldest, max(dt) AS newest, count() AS n FROM s3Cluster(primary, \$BS_TABLE_S3) FORMAT JSONEachRow"` returned oldest `2026-09-04 15:15:56`, newest `2026-10-14 11:37:05`, n=401: the git-data archive holds at least 40 days.
- Command B: the same query with the default (control) tables returned oldest `2026-08-13 15:14:14`: the control archive holds at least 62 days.
- Command C: `doppler run -p soleur -c prd_terraform --only-secrets BETTERSTACK_API_TOKEN -- bash -c '... curl -K - https://telemetry.betterstack.com/api/v1/sources/<id> | jq .data.attributes | {logs_retention}'` returned `logs_retention=90` for both sources (git-data source 2734275 created 2026-09-03; control source created 2026-05-21).
- Consequence: the newest pre-flip row of 2026-10-11 stays readable until about 2027-01-09; the retention-end date 2026-11-12 needs 32 days of age; the measured depth is 40 days. Not shorter than the soak plus lead time, so no change to the evidence source (CTO ruling). The work phase posts these numbers (no ids beyond the table names) on #6897 as an issue comment.
- Command D (journal state, for the layout-signal gate): `... betterstack-query.sh "SELECT dt, JSONExtractString(raw,'plaintext_journal') ... WHERE stage='boot_complete' AND host_name='soleur-git-data' ORDER BY dt DESC LIMIT 3"` returned `dirty` for 2026-10-14 14:34Z, 2026-10-11 12:51Z, 2026-10-08 21:32Z.

### Institutional learnings applied

- `learnings/2026-10-12-a-destructive-single-use-workflow-needs-content-evidence-a-gate-after-it-and-credential-parity.md`: content-level emptiness (the listing), a read-only evidence dispatch before the first destructive one (`wipe_check`), credential parity (the evidence reads run under the same credentials the wipe uses). Its "second approval after the evidence" is answered by the W7-epoch bound plus the owner naming the id, per the CTO F5 ruling.
- `env -u` is not containment; use an `env -i` allow-list and an exact env-name-set assertion; `env -u VAR curl` bypasses stubs; `env -u` cannot scrub shell functions (learnings 2026-09-24, 2026-09-28, 2026-10-11).
- Execute the `notify-failure` bodies under stubs, three states (FAILED / STATE UNKNOWN / quiet on rejected input), `needs.X.outputs.started != 'false'` (learning 2026-10-03).
- `gh run list` truncates at about 20 by default: always `--limit`, and a list that does not reach the stamp is a refusal (learning 2026-07-23).
- A failure-path step needs `always()` or `failure()` (an `if:` with no status function is ANDed with `success()`); `grep -q` under pipefail loses to SIGPIPE (capture first); the errexit-capture lint (`scripts/lint-workflow-errexit-capture.py`, ADR-166); GHA `run:` defaults to pipefail.
- Workflow byte cap ADR-231 (512,000 hard, 490,000 gate); read `workflow_dispatch.inputs` from the YAML.

### Related

PR #10294 (this draft PR), #10132, #10207, #10184, #10210, #10271; issues #6897, #10138, #8571, #9943, #10296, #10297.

## User-Brand Impact

- **If this lands broken, the user experiences:** (1) the LUKS volume detached or deleted: every user's repositories behind the web platform unreachable or lost, and no plaintext rollback copy left to fall back on (a wrong-volume delete is irreversible); (2) the plaintext volume detached but not deleted with the run lost: nothing visible to users, but git-data stays in a state only the typed `wipe_finish` path can finish; (3) the wipe never runs because the mechanism is wrong: an erasure-request residue (identifiers of users who asked for deletion) outlives the 2026-11-12 outer retention date; (4) the wipe run on a non-empty store: repositories destroyed with no copy.
- **If this leaks, the user's data / workflow / money is exposed via:** the Tier-B Hetzner write token (root over any host through rescue/rebuild/re-attach) reaching steps that must never hold it (the loader exports the whole privileged project into `$GITHUB_ENV`); top-level names from the plaintext volume, which can be tenant identifiers, reaching run logs, step summaries, notify emails or the PUBLIC issue #6897; an agent approving its own wipe dispatch.
- **Wedge vector (a held security fix), added after review.** Artifact: the ability to ship a security fix to the rendered `user_data` of `hcloud_server.git_data`, the host behind every tenant's git store. Vector: after the delete and until PR-C merges, state still lists `hcloud_volume.git_data`; a refreshed-away volume plans a new id, and the two jobs that can plan that replace (`git_data_host_replace`, `git_data_host_create` in `apply-web-platform-infra.yml`) REFUSE it, as `tests/scripts/test-git-data-wipe-wedge.sh` pins. So a host-affecting fix cannot ship in that window, while the targeted apply jobs keep running. Mitigation: the PR-C readiness precondition in the runbook ("Before naming `mode=wipe`"); the dispatch-to-merge bound is prose only, and no workflow checks either.
- **Rollback-after-detach vector, added after review.** Artifact: the detached, not-yet-deleted plaintext volume against the 2026-11-12 outer date. Vector: a `mode=rollback` run after the detach makes every later `wipe_finish` refuse `wipe_precondition_rollback_after_stamp` (the precheck runs for the finish too), so the volume outlives the outer date with no workflow path to delete it. Mitigation: prose in the runbook S-table note (the owner records the trade on #6897 and routes it to the CTO and the CLO); the guard retires with #10297.
- **Dispatch and approval by one identity is prose only.** The environment's sole reviewer is also the dispatching identity, so "an agent never approves its own dispatch" is enforced by no workflow step and no environment setting (`web_platform_infra_apply` sets no `prevent_self_review` and no `wait_timer`); it is the accepted position of the ADR-241 amendment of 2026-10-07.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one wrong-volume delete or one leaked write token is a single-user (in fact every-user) incident that cannot be retracted, so the aggregate tier is not enough.

CPO sign-off (Phase 2.6, 2026-10-14): granted with conditions, all written into this plan: a read-only `wipe_check` mode (Phase 4); the wedge test (Phase 6); owner-only environment approval and no headless approval form (Constraints, Phase 4); the `source == tier_b` guard and `exec env -i` containment each with a mutation row (Guard 1; the design's token-blanking step was dropped as false assurance); phase markers before irreversible calls (Guard 3); no names leave the host (Guard 8); wrong-id, LUKS-id, attached-volume and non-empty-store each refuse (Guard 5, Test Scenarios); the emptiness signal resolved without editing `git-data-bootstrap.sh` (Phase 3, CTO ruling). `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Build the wipe-body PR for the owner-decision issue 10138 (DL-2: destroy hcloud_volume.git_data, the plaintext rollback copy) from the MERGED design" [brief] | Phases 1-6 (the `wipe` job and everything it needs) | mapped |
| 2 | "a new mode=wipe / mode=wipe_finish `wipe` job in .github/workflows/git-data-cutover.yml" [brief] | Phase 4 (job, modes, gating, notify) | mapped |
| 3 | "with its census tests" [brief] | Phase 5 (`git-data-cutover-access.test.sh` rows, mutation rows, sibling suites) | mapped |
| 4 | "runbook section" [brief] | Phase 7 (runbook "The wipe", verdict-map rows, tier inventory row) | mapped |
| 5 | "ADR-241 amendment note" [brief] | Phase 7 (`soleur:architecture`, Architecture Decision section) | mapped |
| 6 | "Settle the design's open items V-4, V-8, V-9, V-13/N-19, V-14" [brief] | `decision-challenges.md` rows; Phases 3-4 | mapped |
| 7 | "N-19/V-13 needs a MEASUREMENT of Better Stack archive retention first ... record the measured value and the command" [brief] | Research Insights, Measurement | mapped |
| 8 | "Run the collision probe before planning ... and again after planning" [brief] | Research Insights (probe 1), Phase 8 (probe 2) | mapped |
| 9 | "where it names a live read, plan it as a read-only step of the workflow, never a constant" [brief] | Phase 2 helper verbs `identity --expect attached|detached`/`state`/`actions`/`readback`; Phase 0 re-read | mapped |
| 10 | "bake them into the plan's test/lint list" (the repo gotchas) [brief] | Test and Lint Gate List | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `wipe` job, modes, gating, notify wiring | "a new mode=wipe / mode=wipe_finish `wipe` job" | asked |
| `mode=wipe_check` (read-only) | — | inferred: required by the CPO sign-off condition 1 and the CTO ruling (H9 and the H8 baseline are unverified; a first dispatch that is the destructive one burns an approval against the 2026-11-12 limit); the brief's mode list is not exhaustive ("from the MERGED design" plus the learning) |
| `apps/web-platform/infra/git-data-wipe.sh` helper and its suite | "from the MERGED design" (design section 9: "a new `git-data-wipe` helper") | asked (design-specified) |
| `scripts/lib/git-data-wipe-runs.sh` (run-title classification, W3 interim guard, `wipe_finish` freshness read) | "from the MERGED design" (design 2.1 run discriminator, section 5 item 4) | asked (design-specified) |
| `FLAG_MODE=wipe` in `git-data-flag-precheck.sh` and the pinned soak constant | "from the MERGED design" (design W3) | asked (design-specified) |
| host verb `MODE=wipe_assert` and the snapshot-listing script | "from the MERGED design" (design 3.3) | asked (design-specified) |
| `run-name:` discriminator | "from the MERGED design" (design 2.1) | asked (design-specified) |
| `origin_run` input of `wipe_finish`, the `state`/action-history reads, `refusal`/`phase` extra words | — | inferred: plan-review round 1 (spec-flow, architecture) found dead ends in the design's S3 re-entry (detach unconfirmed, volume already absent, no store-serving proof); the CTO ruled the amended shape (decision-challenges.md, row A); the design's own section 5 requires the re-entry arm to be gated and complete |
| New `git-data-wipe-access.test.sh` for the wipe rows | "with its census tests" | asked (taste default: fewer conflicts in the 277 KB census file) |
| Pinned Doppler install step in `wipe` | — | inferred: architecture review found the cutover's unpinned CLI install would sit in a job holding an environment secret; CTO B |
| `.github/workflows/infra-validation.yml` / shard manifest registration, `scripts/lib/git-data-boot-signal-poll.sh` field-read query | — | inferred: a new suite that is not registered never runs in CI, and W5 needs fields the library's query does not select |
| wedge test | "from the MERGED design" (design section 4 requirement 1, ruled into this PR by the CTO) | asked (design-specified) |
| `infra-credential-tiers-8209.md` inventory row | "from the MERGED design" (design section 6) | asked (design-specified) |
| C4 edge text edits (`github -> hetzner`, `github -> gitDataStore`, `github -> doppler`) | — | inferred: `wg-architecture-decision-is-a-plan-deliverable` and the C4 completeness mandate; the existing edge text says "None of the modes copies, mounts or wipes a volume" and would be falsified by this PR |
| Rung-2 empty-id rehearsal variant + `RUNG2_PLAINTEXT_VOLUME` gate | "from the MERGED design" (design section 9) | descoped to #10296 — justification: CTO ruling 2026-10-14; it binds only a PR that renders an empty plaintext id (PR-C), not the wipe |
| Rollback arm clearing the stamp | "from the MERGED design" (rollback-rehearsal design section 6) | descoped to #10297 — justification: a separate PR per that design; the W3 interim guard covers it here |
| Posting the V-13 numbers on #6897 | "record the measured value and the command" | asked |

### Split Assessment

- Subsystems touched: 6 — `.github/workflows`, `apps/web-platform/infra`, `scripts/lib`, `tests/scripts`, `knowledge-base/engineering` (runbooks, ADR, C4), `plugins/soleur/test` (size/parity suites read, rarely edited).
- Planned files: about 24 (see Files lists) | Estimated changed lines: about 3,500 (the census file alone gains several hundred rows).
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines — exceeded on roots and lines.
- Recommendation: single PR, built in two commit layers (the CTO's boundary: Layer 1 = the read-only `wipe_check` front W1-W7 + teardown + notify clause + precheck/run-lib/helper `phases`,`identity` + host verb without the snapshot port; Layer 2 = everything destructive, `wipe_finish`, the snapshot port, the wedge test, the ADR-241 note) so Layer 1 can ship as its own PR if review or the schedule prefers (a User-Challenge row records that the operator asked for one PR). The pieces are mutually dependent (a workflow job without its census is unmergeable under the existing pins; a census without the job is vacuous), the design and the CTO ruled it one PR ("PR-W"), and the only separable pieces (PR-R, the stamp fix) are already split out as #10296 and #10297. Work-phase commit order below keeps each commit green on its own suite so review can walk it in layers.

## Open Code-Review Overlap

None. (Open `code-review` issues were searched for every planned path: `.github/workflows/git-data-cutover.yml`, the infra scripts and tests, ADR-239/ADR-241, the runbooks, `tests/scripts/test-argv-bearer-sweep.sh`; zero bodies mention them.)

## Architecture Decision (ADR/C4)

### ADR

- **ADR-241 amendment (in scope, a task of Phase 7).** A dated entry in ADR-241's Amendment log, created through `soleur:architecture`, in the shape of `### 2026-10-07 (#9372): web-host-reboot.yml::reboot is a new Tier-B consumer`: title `### 2026-10-XX (#10138): git-data-cutover.yml::wipe is the first Tier-B loader consumer in a mixed-tier workflow` with the actual merge-time date (review fix: `::cutover` only checks that the Tier-B secret is present and never calls the loader, so `wipe` is the FIRST loader consumer in this file, not the second; the retired `web-host-reboot.yml` consumer is gone). Content is the CTO's eight points (decision-challenges.md, row "ADR-241 amendment note") as amended by plan-review round 1: a Tier-B loader consumer in a workflow that also holds Tier-A repo secrets; `doppler-token-legacy` omitted so only the Tier-B arm can run; every post-loader step body begins with `exec env -i <allow-list>` (a credential reaches a child on stdin, never as `env` argv); one `DOPPLER_TOKEN`-carrying fetch-child shape; no W11b (blanking one of about 40 exported names was false assurance and is dropped); the pre-bridge steps W4/W5 use the closed-environment three-flag `env -u` form because no earlier step writes `$GITHUB_ENV` (census-pinned); the whole-project `$GITHUB_ENV` export stays a residual, with the single-name carrier filed as #10300; the inventory row lands in `infra-credential-tiers-8209.md` and the `::cutover` row is untouched; census scope is `tests/scripts/test-infra-privileged-tier-census.sh` (`LOADER_USES`) plus the `git-data-cutover-access.test.sh` pins; it does not change the ADR-239 statement. Cites D1, D2 (owner is the only reviewer, so approval independence is a rule, #8044), D4, D6, D8, D9 (the whole-project `$GITHUB_ENV` export is a residual contained by convention, not closed). No status flip (D1 `adopting`, D2 `proposed`). Add #10138 to the References list.
- **ADR-239:** applied as written; no amendment in this PR (the retention-end amendment is PR-C's, per the design). Not deferred to an issue: PR-C is the already-tracked record PR for #6897.

### C4 views

All three model files were read (the `github -> hetzner`, `github -> gitDataStore` and `github -> doppler` edge texts were read in full) (`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`), not grepped for the feature noun. Enumeration against the change: (a) external human actor: none new (the owner already approves per exact command, `founder -> github`); (b) external system / vendor: Hetzner Cloud API (`github -> hetzner`), Better Stack (`github -> betterstack`), Doppler (`github -> doppler`), Resend (notify) are all already modeled; no new element; (c) containers/data stores touched: `gitDataStore` and the Hetzner volume it sits on, modeled; (d) access relationships that change: three edges whose DESCRIPTIONS the change falsifies, no new edge:
1. `github -> hetzner` (the control-plane API edge): ADD a new sentence (do not edit the existing "the cutover workflow's remaining Hetzner calls through this edge are reads" sentence: it describes `workspaces-luks-cutover.yml`, not this workflow) that `git-data-cutover.yml::wipe` READS through it (identity, action history, read-back, `HCLOUD_TOKEN_READONLY`) and WRITES through it once (one detach and one DELETE of the allow-listed plaintext volume, Tier-B token from the loader, environment-gated, owner-named, `mode=wipe`/`wipe_finish` only).
2. `github -> gitDataStore` (read-only root SSH from `cutover`): the `wipe` job is a second root-SSH consumer; its host verb is read-only toward the store and the volume but creates and removes one transient host-local device-mapper snapshot; the sentence "None of the modes copies, mounts or wipes a volume" is corrected to say that no mode copies or mounts a volume and that `wipe` deletes the retired plaintext volume through the Hetzner API edge, never through the host.
3. `github -> doppler` (Tier-B loader): the consumer list gains the `wipe` job (environment `web-platform-infra-apply`).
Validation: `bash plugins/soleur/test/c4-count-parity.test.sh` (baseline read green on 2026-10-14: "ALL TESTS PASSED"), `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts`. The edit adds no cardinality the parity gate counts; the gate is still re-run.

### Sequencing

This PR (mechanism) -> `wipe_check` dispatches (owner-named, read-only) -> PR-R rehearsal (#10296, paid host, owner-named) in parallel -> `mode=wipe` (owner-named, owner approves the environment) -> PR-C (record and removal, closes #6897; needs a READY state before the dispatch, #8571 or a recorded owner acceptance, and the dispatch-to-merge bound recorded on #6897). The decision is true at merge of this PR (the mechanism exists); the retention end is true only after the owner-named wipe.

## Implementation Phases

Order is RED-first within every phase (`cq-write-failing-tests-before`): write the test rows, watch them fail for the stated reason, then write the code. The machine is heavily loaded: run targeted suites only (named per phase); CI is the merge gate. **Commit layering (CTO, plan-review K):** Layer 1 = the read-only `wipe_check` front (Phases 1 and 2 partly, 3 partly, 4 steps W1-W7 + teardown, matching Phase 5 rows, `wipe_check` runbook subsection); Layer 2 = everything destructive and `wipe_finish`. The last Layer-1 commit is "wipe_check W1 to W7 plus teardown, census green"; the first Layer-2 commit is "mode choice gains wipe and wipe_finish; census order pins move". Each layer's commits leave the pinned suites green.

### Phase 0 — Re-read and baseline (read-only, no code)

- 0.1 Re-read live state with `HCLOUD_TOKEN_READONLY` (`GET /servers?name=soleur-git-data`, `GET /volumes?name=soleur-git-data-store`, `GET /volumes?name=soleur-git-data-luks-store`) and record the pair as evidence (ids by count and equality only in public places). Pin the stub contract's JSON shapes from this real read: `.volumes[].{id,name,server,protection.delete,labels.app,location.name}`, `.servers[].{id,name,created,status}`. The detach (`201`, `.action.id`), `GET /actions/<id>` (`.action.status` in `running|success|error`) and DELETE (`204`) shapes: pin them from the retired `wipe` job at `git show 3ed3e4e6da^:.github/workflows/workspaces-luks-cutover.yml` (and its recorded run logs, if retained) and Hetzner's published API reference now; mark them "unverified live, pinned from precedent" in the helper's header only for what neither source shows. `wipe_check` additionally reads `GET /volumes/<id>/actions` (count and latest command word only) so the action-history shape that `wipe_finish` relies on (CTO A) is verified before any destructive dispatch.
- 0.2 Baseline the pinned suites so the delta is attributable: record the pass counts of `bash apps/web-platform/infra/git-data-cutover-access.test.sh`, `bash apps/web-platform/infra/git-data-flag-precheck.test.sh`, `bash tests/scripts/test-infra-privileged-tier-census.sh`, `bash tests/scripts/test-argv-bearer-sweep.sh` (S3/S4 floors), `bash tests/scripts/test-git-data-boot-signal-poll.sh`, `bash scripts/lib/git-data-store-dirty-scan.test.sh`, `bun test plugins/soleur/test/workflow-file-size.test.ts plugins/soleur/test/terraform-target-parity.test.ts`, `bash plugins/soleur/test/fixture-relative-assert.test.sh`, `bash scripts/lint-workflows.sh`.
- 0.3 Read the retired wipe job's precondition and API steps and the `git-data-plaintext-snapshot-loopback.test.sh` harness (the loopback pattern the snapshot-listing test reuses).
- 0.4 Measure the loader and the W4-W7b path: `startedAt`/`completedAt` of the `uses: ./.github/actions/infra-credentials` step in `gh run view <id> --json jobs` over the last 30 runs of the apply workflows (composite sub-steps are not listed), to size the epoch bounds (CTO D).
- 0.5 Post the V-13 measurement on #6897 (counts, the three commands, the 2027-01-09 horizon; no volume ids, no names).

### Phase 1 — Libraries and the flag precheck (W3, W7b)

Files: `apps/web-platform/infra/git-data-flag-precheck.sh`, `.../git-data-flag-precheck.test.sh`, `scripts/lib/git-data-wipe-runs.sh`, `scripts/lib/git-data-wipe-runs.test.sh`, `scripts/lib/git-data-boot-signal-poll.sh`, `tests/scripts/test-git-data-boot-signal-poll.sh`, `scripts/lib/git-data-store-dirty-scan.test.sh`.

- 1.1 `git-data-flag-precheck.sh`: extend the closed `FLAG_MODE` case with `wipe` and `wipe_check` (report-only: prints `would_refuse=<word>` instead of refusing and exits 0) and `wipe_reread` (the W7b read: flag only; no pin write, no TOFU, no deny-roots probe). Add `readonly WIPE_SOAK_FLOOR_SECONDS=604800` assigned unconditionally (no `${VAR:-}`) with a comment citing ADR-239 and the runbook. Three separate predicates with their own verdict words and exit 5: `wipe_precondition_flag_not_true` (flag exactly `true`; the final `case "$FLAG_MODE:$flag"` currently falls through to `flag=off` exit 0, so `wipe:off` becomes an explicit refusal, `wipe_check:off` a would-refuse), `wipe_precondition_stamp_absent` (stamp present and matching `^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$`, parsed with `date -u -d` in a guarded form, never `|| true`), `wipe_precondition_soak_not_elapsed` (now minus stamp at least the floor; prints `floor_days` derived from the constant). The stamp is read through the existing `read_secret ... --no-exit-on-missing-secret` helper, `prd` config, with the `DOPPLER_TOKEN_PRD` it already holds.
- 1.2 `scripts/lib/git-data-wipe-runs.sh` (sourced, functions only, unit-tested offline like `git-data-rotate-stamp.sh`): (a) `wipe_run_title_class <displayTitle>` returning `wipe|wipe_finish|wipe_check` (full-match `^git-data (wipe|wipe_finish|wipe_check) [0-9]{1,12}$`), `other` (`^git-data (proof|flip|rollback|unfreeze|redeploy)$`), `legacy` (the exact legacy workflow-name title) or `wipe_other` (ANY title starting `git-data wipe`, including a refused dispatch whose free-text `volume_id` made an off-pattern title; ignored by the guard, review fix) or `unparseable` (everything else); (b) `wipe_last_rollback_epoch <gh-run-list-json> <stamp-epoch>` for the W3 interim guard (CTO F): `headBranch==main`, `event==workflow_dispatch`, explicit `--limit 100`, refuses when the list is full and its oldest row is newer than the stamp; a `rollback`-titled run newer than the stamp refuses (a failed rollback counts); a `legacy`-titled run created AFTER the stamp refuses `wipe_precondition_legacy_run_after_stamp`; rows older than the stamp are ignored; no `gh run view` call; unreadable/unparseable refuses; (c) `wipe_origin_run_ok <gh-run-view-json> <volume_id>` for `wipe_finish` (CTO A): title exactly `git-data wipe <volume_id>`, `main`, `workflow_dispatch`, job `wipe` step `wipe_detach_gate` conclusion `success`; anything else refuses. This library is also read by `scripts/lib/git-data-store-dirty-scan.sh` consumers: add a wipe-run jobs payload fixture row to `git-data-store-dirty-scan.test.sh` (a wipe-family run reads clean only because its skipped `cutover` job stays listed; the row proves it stays clean, not `unreadable`).
- 1.3 `scripts/lib/git-data-boot-signal-poll.sh`: add a field-read query for the newest `boot_complete` row (`luks_mounted`, `fence_on_mapper`, `erasure_probe`, `plaintext_empty`, `served_repos`, `plaintext_volume`, `plaintext_journal`; same pinned tables, same three-flag `env -u` read form, no fork of `_git_data_bs_read`), reuse `git_data_boot_complete_freshness` (strictly greater than the server `created`), and an absent-row verdict distinct from query failure. Test rows in `tests/scripts/test-git-data-boot-signal-poll.sh`.
- 1.4 Tests (RED first): flag-precheck rows for each predicate, the pinned value (`WIPE_SOAK_FLOOR_SECONDS=604800` exact), the floor-override rows run a sed-mutated COPY of the script under an `assert_fixture_dir`-guarded `mktemp -d` (the script has no override hook by design: `WIPE_SOAK_FLOOR_SECONDS=0` exported in the environment must still refuse, and a copy mutated to a zero floor must still refuse `stamp_absent`), `wipe:off` refuses, `wipe_reread` writes no pin; run-lib rows over synthesized `gh run list` JSON (no live ids): an off-pattern `git-data wipe 12x` title is `wipe_other` and does not block, a legacy title after the stamp refuses, before the stamp is ignored, full list not reaching the stamp refuses, `wipe_origin_run_ok` rows.

### Phase 2 — The Hetzner helper (W4, W10b, W9, W11, W12)

Files: `apps/web-platform/infra/git-data-wipe.sh`, `apps/web-platform/infra/git-data-wipe.test.sh`.

- 2.1 `git-data-wipe.sh` sources `scripts/lib/bearer-curl.sh` (`if ! source "${GITHUB_WORKSPACE:?}/scripts/lib/bearer-curl.sh"; then ... exit 1; fi`, the errexit-capture lint form), refuses under xtrace with the prologue `scripts/lint-shell-trace-credential-refusal.py` Rules A/B require, never discards `bc_curl` stderr, reads the token only by NAME (`bc_curl NAME 'Authorization:Bearer :HCLOUD_TOKEN_READONLY' -- ...`). It reads the token from its STDIN (one line, `IFS= read -r`), never argv and never inherited env; the caller hands it over by here-string to a `bash -c` child under `env -i` (CTO 12b).
- 2.2 Verbs (each fail-closed, bounded by `--max-time`, shape-validated by anchored regex, fixed verdict word, exit 5): `phases` (prints the closed vocabulary one word per line: `detach_attempted`, `detached`, `delete_attempted`, `delete_sent`, `deleted`; the discoverability probe, whose `expected_output` is the single literal `delete_attempted`), `state` (read-only: prints whether the plaintext volume is attached, detached or absent and whether the LUKS volume is attached; what the `WIPE_STATE_UNKNOWN` email points the owner at, run first in `wipe_check`), `identity --expect attached|detached` (ONE verb replacing the design's `identity`/`finish_identity`/`reread` variants, review fix: R1-R6 per design 3.1: exactly one server named `soleur-git-data`; exactly one volume named `soleur-git-data-store` whose `.id` equals the typed `volume_id`; exactly one `soleur-git-data-luks-store` with a DIFFERENT id attached to the R1 server; `.protection.delete == false`; `.labels.app == "soleur-web-platform"` and equal `.location.name`; with `attached` the plaintext volume's `.server` equals the R1 server (`wipe_not_attached_to_current_host`), with `detached` its `.server` is null; when `.server == null` and `--expect attached` it fails `wipe_volume_already_detached`; classifies `volume_state` `attached|detached|absent` into `$GITHUB_OUTPUT`; the record-writing and the re-read modes differ only by a flag), `actions` (`GET /volumes/<id>/actions`: the newest relevant action is `detach_volume` `success` started at or after the origin run's W9a start with no later `attach_volume`; a running action refuses `wipe_detach_in_flight`; prints the count and latest command word for `wipe_check`), `detach` (runs `record_check` with the W7 constant immediately before the POST, POST expect 201, poll the SAME action every 2 s for at most 30 attempts, never re-POST; any end state other than `success` is `wipe_detach_not_confirmed`), `delete` (DELETE expect 204), `readback` (W12: `GET /volumes/<id>` is 404 AND the name list is empty AND the LUKS volume lists exactly one and attached; 404 with the name still listed is `wipe_readback_name_still_listed`), and `record_check` (existence, mode 0600, epoch; `wipe_assertion_stale`).
- 2.3 Verdict record under `$RUNNER_TEMP` (server id, both volume ids, `created`, an epoch; the binding triple and per-run random are dropped, CTO E), written with the canonical `assert_fixture_dir` operand guard (`plugins/soleur/test/fixture-relative-assert.test.sh` must stay green), mode 0600, never containing a token. Epochs: the W7 epoch is stamped by W7; the W10b epoch by the re-read step (CTO D). No value is ever printed except digits and fixed words.
- 2.4 Test (`git-data-wipe.test.sh`): PATH-shim `curl` state machine (attached -> detaching -> detached -> deleted/404), synthesized ids/tokens only (`cq-test-fixtures-synthesized-only`). Rows: every verdict word in design 3.1/3.4 driven by empty, multi-line, off-shape, duplicate and error stub output; token absent; `HCLOUD_TOKEN_READONLY` absent never falls back to `HCLOUD_TOKEN`; typed id equals the LUKS id; typed id equals a volume attached to another server; two volumes for the name; a detached volume under `--expect attached`; the poll never reaching `success` in 30 attempts; the detach NOT re-sent; DELETE 404 with a present name; the absent-volume `readback`-only path; no token in any recorded argv; no stderr discard on the `bc_curl` calls (the helper joins the S4 population, so `S4_POP_FLOOR` and `S4_SCALLS_FLOOR` rise in Phase 5).

### Phase 3 — The host verb (W7, W10) and the layout-independent signal

Files: `apps/web-platform/infra/git-data-cutover.sh`, `apps/web-platform/infra/git-data-wipe-assert.sh` (host-side script, NOT `file()`-bound into `user_data`; the evidence hash is unaffected, verified with `git_data_rung2_bound_files`), `.../git-data-wipe-assert.test.sh` (loopback + shim), plus rows in `git-data-cutover-access.test.sh` (the G2/G5 pins only).

- 3.1 `MODE=wipe_assert` in `git-data-cutover.sh` (`WIPE_PHASE=pre|finish|post_detach`): ONE ssh session built the `refuse_if_store_unverified_or_not_empty` way (a `facts=( ... )` array, each stage with its own exit code mapped to a fixed verdict word, one fixed-shape output line matched in full by `gd_capture`, anything else `probe_failed rc=<n>`). The script body is sent on stdin to `bash -s` through ONE optional stdin-file parameter added to `gd_capture` (the single ssh site, so the G5 "zero ssh expansions outside `access_gate|gd_capture|gd_exec|resolve_roster`" row stays true) with the typed id and the LUKS id `%q`-quoted into a prefix. `gd_capture` hard-codes `timeout 30`, `</dev/null` and a 4096-byte cap: the wipe call passes an explicit pinned timeout parameter (default unchanged), and a loopback timing row proves a timeout (rc 124) is a tested fail-closed word. `WIPE_PHASE=post_detach` and `finish` run the W10 checks (the by-id link is gone, uncached `dd iflag=direct` block read of `/dev/mapper/git-data` plus a root listing, the store-verified facts): `wipe_finish` runs them too (CTO A, design section 5 item 3).
- 3.2 Checks H1-H10 of design 3.3 (store root on the mapper and marker bound; freeze sentinel absent; `/dev/disk/by-id/scsi-0HC_Volume_<typed id>` resolves to a block device; not the mapper's backing device in BOTH directions; `cryptsetup isLuks` exits 1 (any other code is "unknown", never "plaintext"); not mounted, no holders, no leftover `git-data-pt-snap`; no open handle with a timeout counting as unknown; absolute-zero sectors written/discarded and stable over 2 s and `blockdev --getro` is 1; `/var/lib/cloud/data/instance-id` equals the R1 server id; boot-time and `dt` window bind), each with the design's refusal words. H9 and the H8 `0 0` baseline are UNVERIFIED claims: they are exactly what `wipe_check` measures; the verb fails closed on a mismatch. `wipe_check` also prints `reboot_since_row` (boot time vs the row's `dt`) and the days left to 2026-11-12 so a reboot dead-end is visible early.
- 3.3 Layout-independent listing (CTO option A, forced by the measured dirty journal): port the bootstrap's `plaintext-count unit` (between `BEGIN plaintext-count unit` and `END plaintext-count unit` in `git-data-bootstrap.sh`; that file is read, not edited) into `git-data-wipe-assert.sh` as a read-only dm snapshot over the kernel-read-only device with a COW loop file on tmpfs, `find -mindepth 1 -maxdepth 1 -printf '%y %f\n'` over the snapshot (no `-L`, never dereferencing), the path-typed allowlist of design 3.2 (`repositories` must be a real directory; `lost+found`, `.gc-cursor` and the lock dotfiles must be what they claim), teardown, then a re-check that the origin's sysfs sector counters are unchanged and the device has no holders. The output line carries per-type COUNTS only (CTO G: no digest, no name, no per-name hash, no child of `repositories/` ever leaves the host). Verdicts `wipe_boot_layout_signal_absent|offlist|unparseable`, `wipe_snapshot_teardown_failed`. In `mode=wipe_check` this step is SKIPPED (CLO: `wipe_check` stays a metadata read, no mount, no snapshot); the verb reports `layout_signal=not_run` and the `wipe_check` closing line says `UNVERIFIED: layout listing not exercised`. The listing is therefore first exercised in `mode=wipe` before the loader and the detach, where any failure refuses with nothing changed; the PR body lists this under "NOT proven".
- 3.4 Tests: the loopback test builds a small ext4 image with a deliberately dirty journal and tenant-looking synthesized names, runs the listing, and asserts the origin image bytes are unchanged, the snapshot and loop device are gone, and no synthesized name appears in stdout, stderr, the step summary or any file the script writes (the no-names test the CLO requires). Mandatory pre-merge item: run the loopback test on the CI runner image (the CI kernel's dm and loop behaviour must match the production host before an owner approval is spent on it). Rows for an off-allowlist entry, a symlinked `repositories`, a `repositories` that is a file, an extra top-level directory, an unparseable find line, a teardown failure, a timeout, `getro == 0`, nonzero written/discarded sectors, boot time after the row's `dt` (H10). The `G2` mutating-verb census exempts the new function deliberately and states why (read-only toward the store and the volume; one transient dm snapshot created and removed); the G5 call-site count is re-pinned from 5 to the new exact number.

### Phase 4 — The workflow

File: `.github/workflows/git-data-cutover.yml` (and `.github/actions/*` read, not edited).

- 4.1 Header, inputs and gating: add `run-name:` built from `inputs.mode` and, for the wipe family only, `inputs.volume_id`, emitting exactly the closed title patterns of Phase 1.2 (no trailing space or id for the other modes); add inputs `volume_id` and `origin_run` (strings, default `""`); `mode` gains `wipe`, `wipe_finish`, `wipe_check`; `confirm` tokens `WIPE-GIT-DATA`, `WIPE-FINISH-GIT-DATA`, `WIPE-CHECK-GIT-DATA`. The `cutover` job gains `if: inputs.mode != 'wipe' && inputs.mode != 'wipe_finish' && inputs.mode != 'wipe_check'`; `wipe` gains `if: inputs.mode == 'wipe' || inputs.mode == 'wipe_finish' || inputs.mode == 'wipe_check'`. The cutover confirm step refuses `volume_id` and `origin_run` for every mode it serves. Update the header comment (modes, credentials list, timeout derivation).
- 4.2 `wipe` job: `runs-on: ubuntu-24.04`, `environment: web-platform-infra-apply`, job `concurrency: web-1-swap` (cancel-in-progress false; `wipe_check` keeps the same groups, CTO H), `timeout-minutes: 30` (derived: setup 5 + W4-W7 15 + W7-W11 5 + tail 5; each step carries its own `timeout-minutes` or `timeout` within its share), job outputs `mode`, `started`, `phase` (a `||` chain over the marker steps ordered latest-first: `steps.wipe_readback.outputs.phase || steps.wipe_delete.outputs.phase || steps.wipe_delete_gate.outputs.phase || steps.wipe_detach.outputs.phase || steps.wipe_detach_gate.outputs.phase || steps.wipe_identity.outputs.phase`) and `refusal` (closed vocabulary `volume_already_detached|store_not_serving`, a `||` chain over the identity and W10 steps).
- 4.3 Step table (ids; every later step `if: success()` unless marked; "epoch" = which clock bounds the step). `W`/`F`/`C` = runs in `wipe` / `wipe_finish` / `wipe_check`:

| # | Step id | W | F | C | Notes |
|---|---|---|---|---|---|
| 1 | `wipe_confirm` (W1) | x | x | x | mode/token/`volume_id` shape (`^[0-9]{1,12}$`), `origin_run` numeric and only for `wipe_finish`, `lineage` refused, `GITHUB_RUN_ATTEMPT != 1` refused; writes `mode=` (and the `started` basis) to `$GITHUB_OUTPUT` LAST, after every refusal (V-8), so a refused input is silent |
| 2 | checkout | x | x | x | |
| 3 | `wipe_doppler_install` | x | x | x | inline pinned CLI install (copy of the loader's block); census: literals equal the loader's; no remote `uses:` anywhere in the job (CTO B) |
| 4 | `wipe_flag_precheck` (W3) | x | x | x (report-only) | `DOPPLER_TOKEN: secrets.DOPPLER_TOKEN_PRD`, `FLAG_MODE`; interim rollback-recency guard (`GH_TOKEN`) |
| 5 | `wipe_origin_check` | | x | | `gh run view <origin_run>` -> `wipe_origin_run_ok` |
| 6 | `wipe_identity` (W4) | x (`--expect attached`) | x (`--expect detached`, or `volume_state=absent`) | x (also `state`, `actions`) | `secrets.DOPPLER_TOKEN` fetches `HCLOUD_TOKEN_READONLY` into a masked variable under the pre-bridge three-flag `env -u` form (CTO I; valid only while no earlier step writes `$GITHUB_ENV`, a census row, and W4/W5 precede the bridge); absent token refuses, never falls back; writes `volume_state` and the `refusal` output |
| 7 | `wipe_boot_read` (W5) | x | | x | field query + strict freshness (Phase 1.3); an ABSENT row is distinct from `wipe_boot_unreadable`; non-empty means STOP and route to the CLO |
| 8 | bridge, `wipe_key_fetch`, `wipe_ssh_config` | x | x* | x | *`wipe_finish` with `volume_state=detached` only (W10 needs it); copied from `cutover` |
| 9 | `wipe_host_assert` (W7) | x (`pre`) | x (`finish`) | x (`pre`, listing skipped) | stamps the W7 epoch; closing line of `wipe_check`: `NOT authorization; W3 would be <verdict>; UNVERIFIED: layout listing not exercised` |
| 10 | `wipe_flag_reread` (W7b) | x | x | | `FLAG_MODE=wipe_reread`, child under `exec env -i` with the PRD token on stdin |
| 11 | `wipe_loader` (W8) | x | x* | | `uses: ./.github/actions/infra-credentials` with ONLY `doppler-token-infra-privileged` (V-14); *finish with `volume_state=detached` only |
| 12 | `wipe_detach_gate` (W9a) | x | | | pre-marker checks FIRST (`record_check` stale-epoch bound of the W7 epoch, `steps.wipe_loader.outputs.source == 'tier_b'`), THEN writes `phase=detach_attempted` |
| 13 | `wipe_detach` (W9) | x | | | `helper detach` (write token on stdin; `record_check` with the W7 constant right before the POST); on `success` writes `phase=detached` and the summary IMMEDIATELY |
| 14 | `wipe_post_detach_read` (W10) | x (`post_detach`) | x (`finish`) | | the mapper still serves; failure sets `refusal=store_not_serving` |
| 15 | `wipe_reread` (W10b) | x | x* | | `helper identity --expect detached` with `HCLOUD_TOKEN_READONLY` re-fetched by the single exempt shape; stamps the W10b epoch |
| 16 | `wipe_delete_gate` (W11a) | x | x* | | refuses if more than about 60 s since the W10b epoch, then writes `phase=delete_attempted` |
| 17 | `wipe_delete` (W11) | x | x* | | `helper delete`; on 204 writes `phase=delete_sent` |
| 18 | `wipe_readback` (W12) | x | x | | `helper readback`; writes `phase=deleted` and the evidence summary (CLO wording); the success summary is the tail of this step (V-4); for `volume_state=absent` it is the only post-front step (CTO A) |
| 19 | `wipe_teardown` (W13, `if: always()`) | x | x | x | `exec env -i PATH HOME RUNNER_TEMP SERVER_IP CLOUDFLARED_PID CI_SSH_KEYFILE` with every variable written `NAME="${NAME:-}"` so `set -u` and an early refusal (bridge never ran) cannot add a second red step or a false `VOLUME_DELETED_TEARDOWN_FAILED`; the whole body under `env -i`, not just its children |

  Steps 12-17 have the explicit `if:` strings pinned in full by the census (a `wipe_finish` run makes zero detach POSTs: a stub-log row). Every post-loader step (12-19) begins with the xtrace refusal `case` then `exec env -i <allow-list> bash ...` (the allow-lists are in the decision-challenges row C; no allow-list carries `TF_VAR_*`, `AWS_*`, `TF_STATE_AWS_*` or `DOPPLER_*`; a credential reaches a child on STDIN via `IFS= read -r` in a `bash -c` child, never as `env -i NAME=$value`). W11b (the design's blanking step) is dropped. No remote `uses:` anywhere in the job; neither local action may declare a `post:` hook (`runs.using: composite` for both, census-pinned). Epoch bounds: W9a refuses past the W7-epoch bound sized from the Phase 0.4 measurement (twice the largest observed W7b+loader+gaps, floor 120 s); W11a refuses past about 60 s from the W10b epoch (CTO D).
- 4.4 `notify-failure`: `needs: [cutover, wipe]`; `if:` is two OR-ed clauses, each pairing its own result check with its own `started != 'false'` (a skipped job's empty outputs satisfy `'' != 'false'`, so an unpaired check would email); `MODE` becomes `needs.cutover.outputs.mode || needs.wipe.outputs.mode`; the `case "$MODE"` list gains the three wipe words; the body branches on the originating job BEFORE the generic `FINALIZER_RAN` logic, with words `WIPE_REFUSED_BEFORE_ANY_CALL` ("this run made no irreversible call; it says nothing about earlier runs"; absent phase, `started=='true'`), `WIPE_STATE_UNKNOWN` (absent `started`: points at `helper state` via `wipe_check`), `VOLUME_ALREADY_DETACHED` (`refusal`: carries the `wipe_finish` command with `origin_run`), `STORE_NOT_SERVING_DO_NOT_FINISH` (`refusal`), `DETACH_ATTEMPTED_UNCONFIRMED` ("read the volume first; if detached use the finish command"), `VOLUME_DETACHED` (with the exact `wipe_finish` command), `DELETE_ATTEMPTED_UNCONFIRMED`, `DELETE_SENT_UNCONFIRMED`, `VOLUME_DELETED_TEARDOWN_FAILED`; no word of a wipe run ever carries the unfreeze remedy. An environment approval that is rejected or times out leaves `started` absent and pages as `WIPE_STATE_UNKNOWN` (the existing `cutover` behaviour; the runbook says so). `N-jobkeys` and `N-secrets` stand unchanged (still exactly `GITHUB_TOKEN` and `RESEND_API_KEY`).
- 4.5 `mode=wipe_check`: runs steps 1-4, 6, 7, 8, 9 and 19; steps 10 onward carry the pinned `if:` for `wipe`/`wipe_finish`; it also runs `state` and `actions` and prints `elapsed_s` (W4 to W7) and `reboot_since_row`; it ends with `NOT authorization; W3 would be <verdict>; UNVERIFIED: layout listing not exercised`; notify uses the read-only wording `proof` uses.

### Phase 5 — Census and sibling suites

Files: `apps/web-platform/infra/git-data-cutover-access.test.sh` (cross-job pins only), NEW `apps/web-platform/infra/git-data-wipe-access.test.sh` (all wipe-specific rows, reusing the shared helpers; taste default in decision-challenges.md), `tests/scripts/test-argv-bearer-sweep.sh`, `tests/scripts/test-infra-privileged-tier-census.sh` (read; edit only if a row set moves), `apps/web-platform/infra/suite-shard-legs.tsv` (via `scripts/regenerate-shard-manifest.py`), `.github/workflows/infra-validation.yml` (register the new suites).

Row discipline (taste default): structural pins (`WF-jobs`, `run-name`, mode options, input lists, the `if:` strings) are exact-string rows; mutation rows are kept for token containment, order/binding, markers, identity, the soak floor, the wedge and output honesty. Every pin is the exact new value, never loosened.

- Cross-job pins in the old file: `WF-jobs` -> `["cutover","notify-failure","wipe"]`; `AC9` mode options and `G7/AC9` inputs (`confirm, lineage, mode, origin_run, volume_id`); `WF-inputs-refs` (gains `inputs.volume_id`, `inputs.origin_run` and the `run-name` references) plus an exact-string `run-name` row; the pinned `if:` of `cutover` and `wipe` in full; the local-action set gains `./.github/actions/infra-credentials`; `WF-timeout` stays `>= 120` for `cutover`; `WF9` UNCHANGED; `AC9` `DOPPLER_TOKEN_PRD` amended to exactly three sites with the same pinned env shape (`cutover.flag_precheck`, `wipe.flag_precheck`, `wipe.flag_reread`) and `len(jobs) == 3`; `N-if` (new exact string), `N-jobkeys`, `N-secrets` unchanged, `EXPR_OK` gains `needs\.wipe\.result`, `needs\.wipe\.outputs\.(mode|started|phase|refusal)` and the `||` form; G2 exemption and G5 count re-pins.
- Wipe rows in the new file: the `wipe`-specific step `order` list and the per-step `if:` matrix of Phase 4.3; job `timeout-minutes: 30` at least the sum of the bounds; job `concurrency: web-1-swap`; the `secrets.DOPPLER_TOKEN` per-job count and per-step list (cutover 5 today; wipe adds 5: W4, W5, W6 bridge, W10b, W12; total 10; re-read at build time, never copied); `HCLOUD_TOKEN` is a VALUE SOURCE only in W9 and W11; `HCLOUD_TOKEN_READONLY` only in W4, W10b, W12; the loader appears exactly once, after W7b and before W9a, with ONLY the Tier-B input; `source == 'tier_b'` asserted in W9a BEFORE the marker (a mutation moves it after -> RED); **the first executable statement of every post-loader `run:` matches `^exec env -i `; no `env -i` line carries `NAME=$...` for a credential; the inline Doppler install's two literals equal the loader's two literals parsed from `action.yml`; the job's `uses:` set is `actions/checkout` plus the two local actions (a remote `uses:` goes RED)**; no step prints the environment (`env`, `printenv`, `set` bare, `export -p`, `declare -x`, `compgen -e`); the two local actions' `runs.using` is `composite`; the loader still masks every value per line; no earlier step before W5 writes `$GITHUB_ENV` and W4/W5 precede the bridge.
- Executed notify bodies (stub run with the real `run:` text): a failed `wipe`/`wipe_finish`/`wipe_check` never yields `MODE=unknown`; absent phase + `started=='true'` -> `WIPE_REFUSED_BEFORE_ANY_CALL`; absent both -> `WIPE_STATE_UNKNOWN`; `refusal` words; `deleted` + later failure -> `VOLUME_DELETED_TEARDOWN_FAILED` not `DELETE_SENT_UNCONFIRMED`. Markers: a stub run killed after W9a and before W9's detach returns leaves `phase=detach_attempted`; after W9 `detached`; after W11a `delete_attempted`; before-call markers are their own steps and written before the call (a mutation moves one after its call -> RED); after-success markers are written at W9, W11, W12 themselves. The stub run also confirms (1) outputs publish on a normal failure and (2) a marker written in a step that is then cancelled or timed out still publishes; if either is false the design is re-derived before merge.
- Order (stub log with sequence numbers; the pair count is DERIVED from the live step list, not hard-coded): R1-R6 < W5 < W7 < W7b < loader < detach < post-detach read < re-read < delete < read-back; mutation rows swap each adjacent pair -> RED; the ssh stub is a state machine that flips from "attached, unmounted" to "device absent" at the detach call, so a reordered implementation reads the post-detach world and goes RED.
- Time bounds and TOCTOU: a stub clock past the W7-epoch bound refuses at W9a with the detach NOT sent; a stub clock past 60 s from the W10b epoch refuses at W11a with the DELETE NOT sent; a W10b read that returns a changed name, an attached server or `protection.delete == true` refuses before the DELETE; a flag flipped to non-`true` between W3 and W7b refuses at W7b.
- Emptiness rows (also in `git-data-wipe-assert.test.sh`): nonzero written/discarded sectors; `getro == 0`; a row whose `dt` predates the host boot time; a missing or off-allowlist listing; an absent `repositories` beside a non-allowlisted top-level entry: each refuses.
- `wipe_check` makes no loader, detach or delete call (stub-log row); W3 report-only prints a would-be verdict and exits 0. `wipe_finish` makes zero detach POSTs; with `volume_state=absent` it loads no Tier-B token (the loader step is skipped) and ends `deleted`.
- `test-argv-bearer-sweep.sh`: the helper joins `S4_SCRIPT_MANIFEST`; raise `S4_POP_FLOOR` and `S4_SCALLS_FLOOR` to the measured new values (read, never guessed), raise `S3_CALLS_FLOOR` if a `wipe` workflow step calls `bc_curl` inline, and assert the new calls do not discard stderr. Guard-vacuity floors: every new anti-vacuity floor (rows executed, steps in the `wipe` order list, mutation rows run, no-names corpus size) is a floor on the live count.
- Doc parity row: every `wipe_*` verdict word and every notify word emitted by the helper, host verb, precheck and workflow appears in the runbook verdict map (derived from the code, not hand-counted). Shard manifest: add the new suites to `.github/workflows/infra-validation.yml` and regenerate with `scripts/regenerate-shard-manifest.py --group infra` after committing additions locally; read the diff for rows the plan did not expect.

### Phase 6 — The wedge test

File: `tests/scripts/test-git-data-wipe-wedge.sh` (+ registration).

Property: after the wipe and before PR-C, no workflow other than the git-data dispatch's own gate can plan `hcloud_server.git_data` replace or a create of `hcloud_volume.git_data`. The population is DERIVED (`git ls-files .github/workflows` filtered to workflows running `terraform plan|apply` in the web-platform root, plus their `-target` sets), not a hand list. Two fixtures: (1) the post-delete state: `hcloud_volume.git_data` a create and `hcloud_server.git_data` a replace (user_data id changed); (2) the S3 state (detached, not deleted): a `hcloud_volume_attachment.git_data` create (an unguarded apply would re-attach the plaintext volume to the live host). Each workflow's plan/apply gate (including the per-merge push apply and `scheduled-terraform-drift.yml`, which only plans and is recorded as the second reader of the wedge) is fed each fixture; RED if any path other than the git-data dispatch's own gate (`tests/scripts/lib/git-data-host-replace-gate.sh` plan-time gate: `out_of_scope`) would pass it. The cost is stated in the runbook and PR body: until PR-C merges the gates refuse every web-platform apply on main, security fixes included. If a path cannot be made to refuse, the fallback recorded in the cut list (disabling the push-apply workflows during the window, as the retired `wipe` job asserted) is raised to the owner before merge, not silently adopted.

### Phase 7 — Documents

Files: `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`, `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md`, `knowledge-base/engineering/architecture/decisions/ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md`, the C4 `model.c4`.

- 7.1 Runbook: modes table (three rows with confirm tokens), blast-radius rows (`wipe_check`: nothing; `wipe`/`wipe_finish`: git-data keeps serving, the plaintext volume is detached then deleted, no web restart; a transient host-local device-mapper snapshot during `wipe`), a new section "The wipe (DL-2, #10138 / #6897)": the three copy-paste `gh workflow run` lines with the typed id (and `origin_run` for finish), a bold "never use Re-run failed jobs (a re-run is refused by the attempt-1 rule, silently); a red run with no email means the input was refused", preconditions (flag true + 7 days from the stamp, the pinned constant and how it is relaxed (ADR-239 amendment + CLO ruling only), the latest flip stamp that still allows a dispatch by 2026-11-12 is 2026-11-04, never rotate after the flip, "do not dispatch while another git-data run is pending (a pending run is replaced by any newer dispatch and a wipe waiting for approval holds the web-1-swap queue: approve or reject promptly)", a rejected or timed-out environment approval pages as `WIPE_STATE_UNKNOWN`), the CTO's minimal text ("Before naming `mode=wipe`, #6897 carries (i) the link to a READY PR-C, (ii) the main-dispatched empty-id rehearsal evidence (PR-R #10296) or a recorded owner acceptance of a longer wedge, and (iii) the dispatch-to-merge bound. The workflow does not check these. An agent does not propose the command until each is verified."), the S-table (S1 split by `started` per ruling 12a; S2 detach unconfirmed -> read the volume, `wipe_finish` with `origin_run`; S3 detached; S4 delete unconfirmed -> `wipe_finish` absent branch or read-only re-read; S5; S6 `deleted` + teardown failure), the `wipe_finish` command with `origin_run`, the wedge (drift plan shows a create of `hcloud_volume.git_data`, every web-platform apply on main refuses until PR-C merges, replace lever held, a replace after the flip re-runs first boot against a populated store and fails closed per #8571), the reboot dead-end routing to the CLO, the retention line (a healthy query returning no row after 2027-01-09 means retention was exceeded, route to the CLO), the CLO wording constraints and the standing PA-36(f) line, the interim stamp guard's end of life (delete it once #10297 lands), and the verdict-map rows for every `wipe_*` word. "Last-resort diagnosis" holds anything SSH-class; no primary step prescribes SSH (`hr-no-ssh-fallback-in-runbooks`). The headless `pending_deployments` form is stated as never valid for any wipe mode.
- 7.2 `infra-credential-tiers-8209.md`: a `git-data-cutover.yml::wipe` row (workflow_dispatch; `web-platform-infra-apply`; `DOPPLER_TOKEN`, `DOPPLER_TOKEN_PRD`, `DOPPLER_TOKEN_GIT_DATA_ROOT`, `DOPPLER_TOKEN_INFRA_PRIVILEGED` through the loader; write: one detach and one delete of the allow-listed plaintext volume; B). The `::cutover` row (which carries a stale "no edit is needed" note) is not edited; the new row says it is the first loader consumer in this workflow.
- 7.3 ADR-241 amendment through `soleur:architecture` (see Architecture Decision). 7.4 C4 edge text edits and the three C4 validation runs.
- 7.5 No legal document, no `AGENTS.rules.md`, no privacy/DPD edit.

### Phase 8 — Verification and hand-off

Targeted suites only (load): the Test and Lint Gate List below; collision probe 2 (`gh pr list --search "10138 in:body" --state all`, plus the file-anchor probe over the workflow, the access tests, ADR-239/241 and the runbook against `gh pr list --state open --json number,files`); push only before the PR is armed (never push to an armed or queued PR without asking); PR body carries `Ref #10138`, `Ref #6897` (NOT `Closes`), the Changelog section, the CPO sign-off line, the statement that nothing was dispatched, and a "NOT proven" block (design section 8, plus: the dm-snapshot listing first runs in `mode=wipe`; H9 and the H8 baseline are first measured by `wipe_check`; the detach/delete response shapes are pinned from precedent). Follow-up issues: #10296 (PR-R), #10297 (stamp), #10298 (retire the job after PR-C), #10300 (single-name carrier).

## Files to Edit

- `.github/workflows/git-data-cutover.yml`
- `apps/web-platform/infra/git-data-cutover.sh`
- `apps/web-platform/infra/git-data-flag-precheck.sh`
- `apps/web-platform/infra/git-data-flag-precheck.test.sh`
- `apps/web-platform/infra/git-data-cutover-access.test.sh` (cross-job pins, G2/G5 re-pins only)
- `scripts/lib/git-data-boot-signal-poll.sh` and `tests/scripts/test-git-data-boot-signal-poll.sh` (field-read query, absent-row verdict)
- `scripts/lib/git-data-store-dirty-scan.test.sh` (a wipe-run jobs payload fixture row)
- `tests/scripts/test-argv-bearer-sweep.sh` (floors, S4 manifest)
- `.github/workflows/infra-validation.yml` and `apps/web-platform/infra/suite-shard-legs.tsv` (suite registration)
- `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`
- `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md`
- `knowledge-base/engineering/architecture/decisions/ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md`
- `knowledge-base/engineering/architecture/diagrams/model.c4`
- `tests/scripts/test-infra-privileged-tier-census.sh` (only if the new consumer moves a row set; re-read first)

## Files to Create

- `apps/web-platform/infra/git-data-wipe.sh`, `apps/web-platform/infra/git-data-wipe.test.sh`
- `apps/web-platform/infra/git-data-wipe-assert.sh`, `apps/web-platform/infra/git-data-wipe-assert.test.sh`
- `apps/web-platform/infra/git-data-wipe-access.test.sh` (all wipe-specific workflow census rows)
- `scripts/lib/git-data-wipe-runs.sh`, `scripts/lib/git-data-wipe-runs.test.sh`
- `tests/scripts/test-git-data-wipe-wedge.sh`
- `knowledge-base/project/specs/feat-one-shot-10138-git-data-wipe-body/{decision-challenges.md,tasks.md}`

Not touched (constraints): `AGENTS.rules.md`, any `knowledge-base/legal/**`, `git-data-bootstrap.sh` and every other `file()`-bound payload (the evidence hash and the rung-2 evidence stay valid), `.github/actions/infra-credentials` and `cf-tunnel-ssh-bridge` (read only), the main checkout's `.mcp.json`, `git-data-gc.sh`, `.gc-cursor`, the PR 9466 worktree.

## Test and Lint Gate List (the repo gotchas, named)

Run targeted, in this order, after each phase; CI is the gate.

1. `bash apps/web-platform/infra/git-data-cutover-access.test.sh` (WF9 secret set unchanged; order pins; N-if / N-jobkeys / N-secrets; G2 / G5 re-pins; `AC9`).
2. `bash apps/web-platform/infra/git-data-wipe-access.test.sh`, `bash tests/scripts/test-git-data-boot-signal-poll.sh`, `bash scripts/lib/git-data-store-dirty-scan.test.sh`, `bash apps/web-platform/infra/git-data-flag-precheck.test.sh`, `bash apps/web-platform/infra/git-data-wipe.test.sh`, `bash apps/web-platform/infra/git-data-wipe-assert.test.sh`, `bash scripts/lib/git-data-wipe-runs.test.sh`, `bash tests/scripts/test-git-data-wipe-wedge.sh`.
3. `python3 scripts/lint-workflow-errexit-capture.py` (use `if ! source ...; then ...; exit 1; fi`, never `source ... || {}`); `python3 scripts/lint-workflow-step-env-refs.py`; `python3 scripts/lint-workflow-local-action-checkout.py`; `python3 scripts/lint-shell-trace-credential-refusal.py` (the helper carries the prologue and is in no baseline); `bash scripts/lint-workflows.sh`.
4. The `grep -q` pipe guard (`.claude/hooks/grep-q-pipe-guard.test.sh`): never `cmd | grep -q`; capture into a variable first.
5. `bash tests/scripts/test-argv-bearer-sweep.sh`: S3/S4 populations and floors (raise, read the live number); no `2>/dev/null` on a `bc_curl` call.
6. `bash plugins/soleur/test/fixture-relative-assert.test.sh` (every `rm -rf`/`git -C`/write operand in the new `.sh` files is provably absolute or guarded by the canonical `assert_fixture_dir`; the baseline is not edited).
7. `bash tests/scripts/test-infra-privileged-tier-census.sh` (new `LOADER_USES` consumer; Guard 1 environment).
8. `bun test plugins/soleur/test/terraform-target-parity.test.ts plugins/soleur/test/workflow-file-size.test.ts` (terraform-target-parity pins `git-data-cutover.yml` pin env and the cutover step names; size gate 490,000).
9. `bash plugins/soleur/test/c4-count-parity.test.sh` and the C4 syntax/render tests; `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-10-14-feat-git-data-wipe-body-plan.md`; `python3 scripts/lint-infra-no-human-steps.py` over the plan and the runbook edit.
10. Guard-vacuity floors: every new row family prints its own live count and fails below a pinned floor; the mutation helper runs OUTSIDE command substitution (learning 2026-08-13).

## Guard Contract

### Guard 1 — Token containment after the loader

**Property.** No step of the `wipe` job that runs after the Tier-B loader can read the Hetzner write token, or any other loaded privileged key, except the two steps that must (W9, W11), and no loaded key reaches any child's argv or any output.

**Assembly.** Every step after `wipe_loader` in the `wipe` job (including `if: always()` steps and any step a later change adds), every child process those steps spawn, every `env -i` invocation, the `$GITHUB_ENV` writes (the loader's whole-project export under the plain and `TF_VAR_` names, `TF_STATE_AWS_*`, `DOPPLER_TOKEN_TF`; the plain `HCLOUD_TOKEN` is NOT blanked, which would be false assurance), the inline Doppler install, the two local composite actions (`runs.using`, `post:`), every `uses:` after the loader, and every line that prints the environment. The chokepoint is the stdin credential handoff (`IFS= read -r` in a `bash -c` child under `env -i`); there is more than one consumer (W7b, W9, W10b, W11, W12), all census-enumerated by step id.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Replace a post-loader `env -i ... bash` child with `env -u HCLOUD_TOKEN ...` | RED |
| 2 | Add `HCLOUD_TOKEN="$HCLOUD_TOKEN"` to an `env -i` line (credential in `env(1)` argv) | RED |
| 3 | Add a SECOND post-loader step, after a compliant first, that runs bare (no `env -i`) | RED |
| 4 | Add ANY remote `uses:` to the `wipe` job (before or after the loader), or change the inline Doppler install so its version or sha256 differs from the loader's | RED |
| 5 | Add `printenv` / `export -p` / `declare -x` to any `wipe` step | RED |
| 6 | Make the first executable statement of one post-loader `run:` anything but `exec env -i ...` (the step's own shell then holds the loader's whole-project environment) | RED |
| 7 | Add a `post:` hook or change `runs.using` of either local action | RED |
| 8 | Empty the post-loader step list the census derives (guard's own dispatch: "0 steps checked") | RED (live-count floor) |
| 9 | Pass `doppler-token-legacy` to the loader | RED |

**Harness rows.** (a) A suite edit that stubs the step enumerator to return only W9 must go RED on the floor row; (b) a must-PASS input that is NOT the canonical: a differently ordered but compliant allow-list (same names, other order) and an extra non-secret name (`LC_ALL`) must PASS.

**Anchor.** The census compares to the workflow at HEAD in the same commit, so one diff can weaken both; the independent anchor is the ADR-241 amendment (it states the convention in prose reviewed apart from the test) and the merge-base diff read by the tier census; a `>= N` step floor is paired with set identity (the exact step-id list).

### Guard 2 — Read-before-destroy order and same-session evidence

**Property.** The detach and the delete cannot be issued unless, in the same run, the Hetzner identity read, the boot-time read, the one-session host assertion, the flag re-read, the post-detach host read and the Hetzner re-read of the target all passed, in that order, inside the W7-epoch bound, bound to this run's record.

**Assembly.** The wipe steps W4 -> W11 in `wipe`, the `wipe_finish` front, the helper's `record_check` call sites (W7, W9a, W9, W10b, W11a, W11), the verdict record, the two epoch stamps (W7 and W10b), and the stub log. One chokepoint: `record_check`; call sites are enumerated by step id.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Swap any two adjacent steps in the stub-driven order (the pair count is derived from the live step list) | RED |
| 2 | Move the host assertion after the detach (the ssh stub flips to "device absent" at the detach call) | RED |
| 3 | Add a second pre-destructive read after a compliant first that returns a changed fact | RED |
| 4 | Stub clock past the W7-epoch bound at W9a / W11a | RED (refusal word, detach NOT sent) |
| 5 | Remove one `record_check` call site | RED |
| 6 | Remove the W10b epoch re-stamp so W11a is bounded from the W7 epoch | RED |
| 7 | Make the order-recording stub log silent (0 calls recorded) | RED (floor) |
| 8 | In `wipe_finish`, skip writing its own verdict record | RED (refuses at W10b) |

**Harness rows.** (a) Suite edit: delete the "device absent at detach" state flip -> the order rows must go RED rather than pass on a stale fixture; (b) must-PASS: a reordering of two INDEPENDENT reads inside W4 (R2 before R3) that the contract permits.

**Anchor.** The stub contract is derived from the real read-only Hetzner call of Phase 0.1 (shapes) and the retired wipe job (action sequence); the independent move is `wipe_check`, whose live W1-W7 run under real credentials is recorded by the owner before `mode=wipe`.

### Guard 3 — Progress markers before irreversible calls, and what each phase means

**Property.** A marker naming an irreversible call is committed before the call starts, an absent phase is never read as "nothing changed" unless `started` proves the job published outputs, and no wipe-family failure ever carries the unfreeze remedy.

**Assembly.** The marker steps W9a, W9, W11a, W11, W12 and the `phase` `||` chain, `started`, `notify-failure` `case "$MODE"` and body branches (every originating job, every phase value), the S1-S6 table in the runbook.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Move a before-call marker after its call | RED |
| 2 | Merge W9a into W9 (marker no longer its own step) | RED |
| 3 | Reorder the `phase` chain so `delete_sent` precedes `deleted` | RED (S6 row) |
| 4 | Drop `wipe_finish` from the `case "$MODE"` list | RED (`MODE=unknown`) |
| 5 | Make W1 write `mode=` before the `volume_id` refusal | RED (typo emails) |
| 6 | Add a wipe word that shows the unfreeze remedy | RED |
| 7 | Drop `refusal` from the notify mapping, or make `VOLUME_ALREADY_DETACHED` omit the finish command | RED |
| 8 | Remove one phase value from the notify mapping (guard's own dispatch: unmapped phase) | RED |

**Harness rows.** (a) A stub run that kills the job after W9a must leave `detach_attempted` and a second killed after W11a must leave `delete_attempted`; a suite that only greps the YAML for the marker strings must go RED against an executed-body row; (b) must-PASS: a run with phase absent and `started=='true'` produces `WIPE_REFUSED_BEFORE_ANY_CALL` (differs from the canonical failure arm).

**Anchor.** The executed notify bodies are run under stubs with the real `run:` text extracted from the workflow, so a body change cannot hide behind a static substring row; the open question of whether outputs publish from a cancelled/timed-out step is answered by the stub run and re-derived before merge if false.

### Guard 4 — Closed dispatch surface and job gating

**Property.** Exactly the three wipe modes start the `wipe` job and none of them can start `cutover`; `volume_id` is accepted only by the wipe modes and only as 1-12 digits; no wipe mode can be re-run.

**Assembly.** `on.workflow_dispatch.inputs` (names, `mode` options), the two job-level `if:` strings, the confirm tokens, `W1` refusals, `run-name`, `GITHUB_RUN_ATTEMPT` handling, `WF-inputs-refs`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop `inputs.mode != 'wipe_check'` from the `cutover` `if:` | RED |
| 2 | Add a fourth wipe-ish mode to the choice without a `wipe` `if:` clause | RED |
| 3 | Accept `volume_id` in `mode=flip` | RED |
| 4 | Accept `GITHUB_RUN_ATTEMPT=2` in one wipe mode while refusing the others (the second member) | RED |
| 5 | Change the `run-name` expression so a rollback title gains a trailing id | RED |

**Harness rows.** (a) A suite edit deleting the `volume_id` input from the fixture workflow must make the refusal rows RED (not skip); (b) must-PASS: `volume_id` with leading zeros of length 12 passes shape.

**Anchor.** Exact-string pins of both `if:` strings and the `run-name` expression; the anchor outside the diff is the runbook's dispatch strings, compared by the doc-parity row.

### Guard 5 — Identity: the typed id must equal what Hetzner names, and is never the LUKS volume

**Property.** The delete target is the volume the API returns for the name `soleur-git-data-store`, equal to the typed digits, attached to the one `soleur-git-data` server (or detached for `wipe_finish`), distinct from the LUKS volume, undeleteable-protection off, and the host's by-id device for that id is not the mapper's backing device.

**Assembly.** Helper verbs `identity --expect attached|detached` (used by W4, the `wipe_finish` front and W10b), `state`, `actions`, `readback`; host checks H3-H5; the typed-id shape check; the stub contract.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Typed id equals the LUKS id | RED (`wipe_target_is_luks`) |
| 2 | Typed id equals a volume attached to another server | RED |
| 3 | Two volumes returned for the name (second member after a compliant first) | RED |
| 4 | By-id device of the typed id is the mapper's backing device | RED |
| 5 | `protection.delete` unreadable or true | RED |
| 6 | Remove the LUKS-still-attached presence proof from `readback` | RED |

**Harness rows.** (a) Stub returns zero volumes: the helper must refuse, not default to the typed id; (b) must-PASS: an API response with extra unknown JSON fields and different key order.

**Anchor.** Ids are synthesized in tests and live-read in production; the independent evidence is `wipe_check`'s printed pair.

### Guard 6 — The soak floor is one pinned constant

**Property.** No input, environment value or variable can lower the 7-day soak, flag-true, stamp-present and stamp-newer-than-last-rollback are separate predicates, and the floor changes only by a reviewed diff.

**Assembly.** `git-data-flag-precheck.sh` (`FLAG_MODE=wipe|wipe_check|wipe_reread`), the workflow step env, the run lib's rollback-recency read, the runbook number.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Change `604800` to another value | RED (pin row) |
| 2 | Make the constant `${WIPE_SOAK_FLOOR_SECONDS:-604800}` | RED |
| 3 | Export `WIPE_SOAK_FLOOR_SECONDS=0` in the test env | still refuses (RED if it passes) |
| 4 | Set the floor to zero in a stub and keep the stamp absent | still refuses `stamp_absent` |
| 5 | Drop the rollback-recency predicate | RED |

**Harness rows.** (a) Suite edit: remove the stamp fixture -> the soak rows must go RED, not pass vacuously; (b) must-PASS: a stamp 8 days old in a different valid timestamp zone suffix `Z` form.

**Anchor.** The value is also stated in the runbook and ADR-239 text; the doc-parity row compares them; relaxing it needs the ADR amendment and a CLO ruling (decision-challenges row).

### Guard 7 — The wedge

**Property.** After the wipe and before PR-C no workflow other than the git-data dispatch gate can plan a git-data host replace or a create of `hcloud_volume.git_data`.

**Assembly.** All workflows that run `terraform plan|apply` in the web-platform root (derived), their `-target` sets, the git-data plan-time gate and post-apply backstop, the drift workflow (plan only).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add `hcloud_server.git_data` to a non-git-data job's `-target` set | RED |
| 2 | Add an untargeted apply path | RED |
| 3 | Add a second such workflow after a compliant first | RED |
| 4 | Feed the fixture with the volume as `no-op` instead of `create` | RED (fixture-sensitivity row) |
| 5 | Empty the derived workflow population | RED (floor) |

**Harness rows.** (a) A suite edit that makes the fixture loader return an empty plan must go RED; (b) must-PASS: a pre-wipe canonical plan fixture.

**Anchor.** The population is derived from `git ls-files`, so a new workflow cannot hide; the gate fixtures are shared with `tests/scripts/test-git-data-host-replace-gate.sh`.

### Guard 8 — Output honesty: no names, no over-claiming

**Property.** No name read from the plaintext volume reaches any output stream or file, and no string the run or the runbook prints claims more than "the device was deleted".

**Assembly.** The host script's stdout/stderr, the helper's output, `$GITHUB_STEP_SUMMARY` / `$GITHUB_OUTPUT` / annotations, the notify body, the runbook wipe section and the standing PA-36(f) line; the verdict words versus the runbook verdict map.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Make the listing print one synthesized name | RED |
| 2 | Add "erased" / "wiped" / "secure" / "no copies" to a summary line or the runbook section | RED (forbidden-phrase row) |
| 3 | Emit a `wipe_*` verdict word with no runbook row | RED (parity row) |
| 4 | Print a per-name hash or any digest of the listing | RED |
| 5 | Empty the synthesized-name corpus (guard's own dispatch) | RED (floor) |

**Harness rows.** (a) Suite edit that removes the corpus names from the fixture image must go RED, not pass; (b) must-PASS: a listing wholly inside the allowlist prints its per-type counts.

**Anchor.** The CLO reviews the actual strings before merge (decision-challenges row); the forbidden-phrase list is the CLO's, quoted in the test header.

## Domain Review

**Domains relevant:** engineering, legal, product (sign-off only)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Rulings on V-4, V-8, V-9, V-13, V-14, the ADR-241 note, the emptiness signal, `wipe_check`, `wipe_finish`, concurrency, the helper, five design defects (12a-e), PR-W scope and the soak floor are recorded as `Ruled by CTO agent, 2026-10-14` rows. Design defects fixed in this plan: absent-phase semantics (a), the `env -i NAME=$value` argv leak (b), the closed `FLAG_MODE` case and the `flag=off` fall-through (c), the `needs` list against the pinned notify rows (d).

### Legal (CLO)

**Status:** reviewed
**Assessment:** The GDPR gate passes with the wording constraints (Guard 8); the CTO later cut the digest, so only counts are reported; the end event claims the device only; `wipe_check` stays a metadata read; the soak floor as a single pinned constant is adequate; the build may merge with no legal-document edit; pre-dispatch items (record-PR wording, snapshot procedure sight, off-allowlist routing, V-13 on #6897) are owner/CLO steps, not this PR's. `soleur:gdpr-gate` is advisory; the CLO agent performed the equivalent assessment on the plan content.

### Product (CPO)

**Status:** reviewed
**Assessment:** Sign-off granted with conditions (written into this plan, see User-Brand Impact). Tell the owner and the CLO now that the flip chain plus the 7-day soak must precede the wipe and no flip is dated: with the outer date 2026-11-12, a flip stamped after 2026-11-04 cannot satisfy the soak in time. That is a schedule and legal-risk call for the owner and the CLO, not decided here.

### Product/UX Gate

**Tier:** none (no user-facing page, component or copy; infrastructure workflow only).
**Decision:** N/A — no UI surface in Files to Create or Edit.
**Pencil available:** N/A (no UI surface)

## Infrastructure (IaC)

No new infrastructure resource is introduced: no `.tf` file is edited, no server, vendor account, DNS record, secret or Doppler key is created (the Tier-B and Tier-A tokens already exist and are referenced by name). The only infrastructure effect is the DESTRUCTION of an existing Terraform-managed volume by an owner-named workflow dispatch through the Hetzner API, followed by PR-C's Terraform removal with `removed { lifecycle { destroy = false } }` (a separate PR; the wedge is PR-W's test). The plan prescribes no manual provisioning step.

### Terraform changes

None in this PR (PR-C owns `git-data.tf`, `git-data-luks.tf` comment cross-refs and the ledger row). No sensitive variable is added.

### Apply path

Not applicable (no apply). The destroy is a workflow-API delete, not a Terraform apply; its blast radius: git-data keeps serving from the LUKS volume; the plaintext volume is detached and deleted; no web restart.

### Host fan-out

No `terraform_data` SSH provisioner is added or changed.

### Distinctness / drift safeguards

The wedge (a refreshed-away volume planning a create and a ForceNew host replace) is the drift risk this plan guards (Guard 7). `dev != prd`: the workflow reads only `prd` and `prd_terraform`.

### Vendor-tier reality check

Hetzner volume delete protection is off for this volume (`protection.delete=false`, read 2026-10-14); the run never lifts protection (lifting is a Terraform change of its own). Better Stack retention is 90 days configured, at least 40 days measured deep.

## Encryption Posture

```yaml
at_rest:
  - store:            hcloud_volume.git_data (soleur-git-data-store) — the retained PLAINTEXT rollback copy this PR builds the means to destroy
    mechanism:        plaintext-exception
    evidence:         scripts/encryption-posture-ledger.json row hcloud_volume.git_data (expires_on 2026-11-12, tracking #6897); ADR-239 Amendments 2026-10-09 and 2026-10-12
    defends_against:  nothing at rest; it is mounted never after boot, kernel read-only, never written (ADR-239 D2)
    does_not_defend:  a seized/RMA'd disk, a raw volume snapshot, any holder of the volume or a provider snapshot; id-bearing lock residue may sit on it (unmeasured)
    disclosed_as:     not-publicly-claimed (legal wording is #8551/#10136 and untouched here)
    live_verification: available (Hetzner API read of the volume; the host listing in the destructive session reports per-type counts only)
in_transit:
  - connection:        runner -> api.hetzner.cloud (detach, action poll, delete, reads)
    enforced_at:       apps/web-platform/infra/git-data-wipe.sh (bc_curl, scripts/lib/bearer-curl.sh: no redirects, no proxy, TLS verification default on)
    tls:               HTTPS, TLS 1.2+ (curl default)
    cert_verification: on
    does_not_defend:   a compromised runner or Hetzner account; the bearer is on stdin, not on the wire in clear
    disclosed_as:      not-publicly-claimed
  - connection:        runner -> git-data host via the Cloudflare tunnel bridge and web-1 direct-tcpip hop (host verb)
    enforced_at:       .github/actions/cf-tunnel-ssh-bridge and the generated ssh_config (StrictHostKeyChecking yes, pinned keys, ADR-237)
    tls:               SSH with pinned ED25519/ECDSA host keys (no TLS)
    cert_verification: on (pinned host key)
    does_not_defend:   a pinned key authenticates the host, not its answers (ADR-220)
    disclosed_as:      not-publicly-claimed
exception:
  justification:      the plaintext volume exists only until the owner-named delete ends it; this PR adds the mechanism, it adds no store and no new exception
  tracking_issue:     "#6897"
  reevaluate_when:    the wipe completes (PR-C deletes the ledger row) or 2026-11-12 passes (CLO re-ruling, ADR-239 Amendment 2026-10-12)
  expires_on:         2026-11-12
```

## Observability

```yaml
liveness_signal:
  what:            notify-failure job (opens or comments on the ci/git-data-cutover issue and sends the Resend ops email) on any failed or cancelled wipe-family run; phase markers and evidence lines in the run step summary
  cadence:         per run (the wipe is dispatched by the owner, never scheduled)
  alert_target:    GitHub issue ci/git-data-cutover (primary) and the ops email (secondary, best-effort)
  configured_in:   .github/workflows/git-data-cutover.yml (notify-failure)
error_reporting:
  destination:     GitHub Actions run annotations ::error title=git-data-wipe verdict=<word> (layer 6: workflow-run log, synchronous) plus the notify issue
  fail_loud:       non-zero exit with a fixed verdict word from the closed list in the runbook verdict map; no value other than digits and fixed words is printed
failure_modes:
  - mode:          runner lost or job timed out mid-sequence (no outputs published)
    detection:     absent started output -> notify word WIPE_STATE_UNKNOWN (layer 6, notify job)
    alert_route:   ci/git-data-cutover issue + ops email
  - mode:          refusal before any irreversible call (W3 soak, R2 mismatch, W5 unreadable, W7 host refusal, loader failure)
    detection:     absent phase with started=true -> WIPE_REFUSED_BEFORE_ANY_CALL (layer 6)
    alert_route:   ci/git-data-cutover issue + ops email
  - mode:          detach POST may have been accepted but not confirmed
    detection:     phase=detach_attempted -> DETACH_ATTEMPTED_UNCONFIRMED (layer 6)
    alert_route:   ci/git-data-cutover issue + ops email
  - mode:          volume detached but not deleted
    detection:     phase=detached -> VOLUME_DETACHED with the exact wipe_finish command (layer 6)
    alert_route:   ci/git-data-cutover issue + ops email
  - mode:          delete sent but not confirmed, or confirmed and teardown failed
    detection:     phase=delete_attempted|delete_sent -> DELETE_*_UNCONFIRMED; phase=deleted + later failure -> VOLUME_DELETED_TEARDOWN_FAILED (layer 6)
    alert_route:   ci/git-data-cutover issue + ops email
  - mode:          plain mode=wipe dispatched against an already-detached volume, or the mapper check fails after a detach
    detection:     refusal=volume_already_detached -> VOLUME_ALREADY_DETACHED (with the exact wipe_finish command); refusal=store_not_serving -> STORE_NOT_SERVING_DO_NOT_FINISH (layer 6, notify job)
    alert_route:   ci/git-data-cutover issue + ops email
  - mode:          Better Stack boot_complete row unreadable or absent
    detection:     wipe_boot_unreadable vs the distinct absent-row verdict (layer 6; the query reads the git-data Better Stack source, an asynchronous layer-3-class store, read synchronously by the job)
    alert_route:   run annotation; the runbook routes an absent row after 2027-01-09 to the CLO
logs:
  where:           GitHub Actions run logs and step summary for git-data-cutover.yml; the host verb answers on the ssh session (captured by the job), no host-side log is relied on
  retention:       the repository log retention setting (90 days configured; run records are listed longer, runbook "Re-baselining the pinned runs")
discoverability_test:
  command:         bash apps/web-platform/infra/git-data-wipe.sh phases
  expected_output: delete_attempted
```

## Acceptance Criteria

### Functional Requirements

- [ ] `.github/workflows/git-data-cutover.yml` has a `wipe` job serving exactly `mode` in `wipe|wipe_finish|wipe_check`, the `cutover` job is skipped for those three (full `if:` strings pinned), `volume_id` is a new input valid only for them (`.github/workflows/git-data-cutover.yml` inputs and `wipe_confirm`; census `WF-jobs`, `G7/AC9`, `WF-inputs-refs`).
- [ ] W3 refuses unless the flag is exactly `true`, the stamp is present and parseable, and at least `WIPE_SOAK_FLOOR_SECONDS=604800` have elapsed, plus the interim stamp-newer-than-last-rollback guard (`apps/web-platform/infra/git-data-flag-precheck.sh`, `scripts/lib/git-data-wipe-runs.sh`; Guard 6).
- [ ] The helper's `identity --expect`/`state`/`actions`/`detach`/`delete`/`readback` verbs enforce R1-R6, the 30-attempt poll, 204/404 handling and the LUKS presence proof; the typed id must equal the API id and differ from the LUKS id (`apps/web-platform/infra/git-data-wipe.sh`; Guard 5).
- [ ] The host verb asserts H1-H10 in ONE session (explicit pinned `gd_capture` timeout) and produces the layout-independent listing as per-type counts only from a read-only dm snapshot (not in `wipe_check`, which prints `UNVERIFIED: layout listing not exercised`); no name and no digest leaves the host; the loopback test passed on the CI runner image (`apps/web-platform/infra/git-data-cutover.sh` `MODE=wipe_assert`, `apps/web-platform/infra/git-data-wipe-assert.sh`; Guard 8).
- [ ] The Tier-B loader is used once, with only the Tier-B input, after W7b and before W9a; `source == 'tier_b'` is asserted before the `detach_attempted` marker; the first statement of every post-loader step is `exec env -i <allow-list>` with stdin credential handoff; the Doppler install is pinned and the job has no remote `uses:`; there is no W11b (`.github/workflows/git-data-cutover.yml` steps `wipe_doppler_install`, `wipe_loader`, `wipe_detach_gate`, `wipe_teardown`; Guard 1).
- [ ] Markers `detach_attempted`, `detached`, `delete_attempted`, `delete_sent`, `deleted` are written before/at the calls named in Phase 4.3 and mapped to the seven notify words; no wipe word carries the unfreeze remedy (`.github/workflows/git-data-cutover.yml` `notify-failure`; Guard 3).
- [ ] `mode=wipe_check` runs W1-W7 with W3 report-only, makes no loader/detach/delete call and ends with `NOT authorization` (stub-log row).
- [ ] `mode=wipe_finish` takes `volume_id` and `origin_run`, verifies the origin run (title, `main`, dispatch, W9a `success`) and the Hetzner action history (newest relevant action `detach_volume` success, no later attach), re-runs the mapper check, and ends `deleted` through the detached branch or the absent-volume `readback`-only branch (no Tier-B token loaded); a plain `mode=wipe` against a detached volume fails `wipe_volume_already_detached` with the finish command (`scripts/lib/git-data-wipe-runs.sh` `wipe_origin_run_ok`, `apps/web-platform/infra/git-data-wipe.sh` `identity`/`actions`/`readback`; Phase 4.3).
- [ ] The wedge test is green and its population is derived (`tests/scripts/test-git-data-wipe-wedge.sh`; Guard 7).
- [ ] Runbook section "The wipe" with the dispatch strings, S1-S6, the preconditions, the wedge note, the retention line, the CLO wording constraints and a verdict-map row for every `wipe_*` word (doc-parity row green); `infra-credential-tiers-8209.md` has the `::wipe` row; the ADR-241 amendment entry exists with the CTO's eight points and #10138 in References; the three C4 edge texts are corrected and the C4 tests pass.
- [ ] The V-13 numbers and commands are posted on #6897.

### Non-Functional Requirements

- [ ] No secret value is printed anywhere; no credential on any argv (`bc_curl` stdin config; `env -i` handoff by stdin); no `2>/dev/null` on a `bc_curl` call.
- [ ] The headless `pending_deployments` approval form is documented as never valid for a wipe mode, and nothing in the PR performs it.
- [ ] `git-data-bootstrap.sh` and every `file()`-bound payload are byte-unchanged (`git diff --stat` shows none; the rung-2 evidence stays valid).
- [ ] Workflow size stays under the 490,000-byte gate; the PR body states what was NOT proven (design section 8).
- [ ] NFR register assessment (`soleur:architecture assess` against `knowledge-base/engineering/architecture/nfr-register.md`).

### Quality Gates

- [ ] Every item of the Test and Lint Gate List passes locally (targeted) and in CI.
- [ ] Collision probe 2 is clean.
- [ ] `soleur:engineering:review:user-impact-reviewer` ran (threshold `single-user incident`); the CLO reviewed the actual strings.
- [ ] No legal document, no `AGENTS.rules.md` change; nothing dispatched, applied or deleted by the PR or its CI.

## Test Scenarios

### Acceptance Tests (RED phase targets)

- Given a stub Hetzner where `soleur-git-data-store` has id A attached to the one server and the LUKS volume id B, when `wipe_check` runs with `volume_id=A`, then W3 prints a would-be verdict, W4-W7 pass and no loader/detach/delete call is recorded (unit/integration, stub).
- Given the same state and a flag `true` stamped 8 days ago, when `mode=wipe` runs, then the stub log order is R1-R6 < W5 < W7 < W7b < loader < detach < post-detach read < re-read < delete < read-back and the run ends `deleted` (integration, stub).
- Given a volume left detached by a run whose detach poll gave up (W9a `success`, W9 failed), when `mode=wipe_finish` runs with that `volume_id` and `origin_run`, then it verifies the origin run and the action history, runs the mapper check and ends `deleted`; with a wrong title, a non-`main` run, an origin whose W9a did not succeed, or a later `attach_volume` it refuses (unit, run lib and stub).
- Given the volume is already absent after a sent delete, when `mode=wipe_finish` runs, then no loader, detach or delete step runs and `readback` writes `phase=deleted` with the origin run's DELETE conclusion (integration, stub).
- Given a plain `mode=wipe` against a detached volume, then `wipe_volume_already_detached` and the notify body carries the exact `wipe_finish` command (executed notify body).

### Regression / Edge Cases

- Given `volume_id` equals the LUKS id, equals a volume attached elsewhere, or two volumes list for the name, then `wipe_target_is_luks`, `wipe_not_attached_to_current_host`, `wipe_volume_count` and no detach is sent (unit).
- Given the snapshot listing finds a symlinked `repositories`, an extra top-level directory or an unparseable line, then `wipe_boot_layout_signal_offlist|unparseable` and the loader never runs (unit, loopback).
- Given `getro == 0`, nonzero written sectors or a boot time after the row's `dt`, then `wipe_ro_flag_lost|wipe_device_written|wipe_boot_generation_mismatch` (unit).
- Given the stale-epoch bound exceeded at W9a, then the refusal is clean and the notify word is `WIPE_REFUSED_BEFORE_ANY_CALL`, not `DETACH_ATTEMPTED_UNCONFIRMED` (executed notify body).
- Given the job is killed after W9a, after W9, after W11a and after W12, then the phases and notify words are `detach_attempted`, `detached`, `delete_attempted`, `deleted` + `VOLUME_DELETED_TEARDOWN_FAILED` (executed notify body).
- Given `WIPE_SOAK_FLOOR_SECONDS=0` exported, then W3 still uses 604800 (unit); given a stamp older than the last rollback run, W3 refuses.
- Given any wipe summary or annotation, then no synthesized tenant name from the loopback fixture appears and no forbidden phrase ("erased", "wiped", "secure", "no copies") is present (corpus row).

### Integration Verification (for `soleur:qa`)

- **API verify (read-only):** `doppler run -p soleur -c prd_terraform --only-secrets HCLOUD_TOKEN_READONLY -- bash -c '...GET /volumes?name=soleur-git-data-store'` expects exactly one volume (re-run in Phase 0.1; never a delete).
- **Static:** `bash apps/web-platform/infra/git-data-wipe.sh phases` prints the closed vocabulary.
- Nothing destructive or dispatching runs in QA.

## Dependencies & Risks

- **Schedule (owner/CLO, not decided here):** the wipe needs a flip plus a 7-day soak first, no flip is dated, and the outer date is 2026-11-12 (the latest stamp that still allows a dispatch is 2026-11-04). The CTO ruled 2026-10-13 to tell the CLO if it looks unable to land by about 2026-11-05. PR-R (#10296) needs a paid-host rehearsal and should start in parallel.
- **Unverified claims the build must not lean on:** H9 (`/var/lib/cloud/data/instance-id` equals the Hetzner server id) and the H8 `0 0` baseline are measured first by `wipe_check`; the detach/poll/DELETE response shapes are pinned from precedent and verified live only by the first destructive run's fail-closed reads.
- **The snapshot listing is first exercised in `mode=wipe`** (not `wipe_check`, per the CLO); a failure refuses before the loader. It is a port of a tested unit with a loopback test.
- **Loaded machine:** targeted suites only; the 277 KB access census is slow; CI is the gate.
- **PR-C preconditions** (#8571 or a recorded owner acceptance; a READY PR-C; the dispatch-to-merge bound) are runbook text, not machine-enforced.
- **Reboot dead-end** (H8/H10 after any host reboot) is an accepted residual routed to the CLO; no flag accepts an owner-supplied read.
- **Collision probe 2 (after planning, 2026-10-14):** the four `10138 in:body` PRs are all merged; one open sibling overlaps by file anchor: draft PR #10185 (`feat-one-shot-10119-10120-10091-10092-10093-argv-bearer-followups`, ADR-280 and the argv-bearer sweep family). The shared hot spots are the literal floors in `tests/scripts/test-argv-bearer-sweep.sh` (`S3_CALLS_FLOOR`, `S4_POP_FLOOR`, `S4_SCALLS_FLOOR`): merge main before the first push of the sweep edit and again before review, take main's line and re-apply this PR's one-token change, re-run the sweep after each resolution (learning: single-literal hot spots).
- **Precedent drift:** the retired workspaces `wipe` job is read for sequence only; its fallback to the read/write token is never reused.

## References & Research

- Design: `knowledge-base/project/specs/archive/20261013-002507-feat-one-shot-git-data-luks-cutover-8211/design-wipe-body-pr.md`, `decision-challenges.md`, `design-rollback-rehearsal.md`, `design-9943-liveness-precheck.md`.
- ADR-239 (Amendments 2026-10-09, 2026-10-12, 2026-10-13 #10175 and #10138), ADR-241, ADR-280, ADR-231, ADR-283.
- Runbooks: `git-data-luks-cutover-5274.md`, `infra-credential-tiers-8209.md`.
- Code: `.github/workflows/git-data-cutover.yml`, `.github/actions/infra-credentials/action.yml`, `.github/actions/cf-tunnel-ssh-bridge`, `apps/web-platform/infra/git-data-cutover.sh`, `git-data-flag-precheck.sh`, `git-data-bootstrap.sh` (plaintext-count unit), `scripts/lib/bearer-curl.sh`, `scripts/lib/git-data-boot-signal-poll.sh`, `scripts/lib/git-data-rotate-stamp.sh`, `tests/scripts/lib/git-data-host-replace-gate.sh`.
- Precedent: `git show 3ed3e4e6da^:.github/workflows/workspaces-luks-cutover.yml` (job `wipe`).
- Issues: #10138, #6897, #10296 (PR-R), #10297 (stamp fix), #8571, #9943, #10166, #10175.
- Ruling record: `knowledge-base/project/specs/feat-one-shot-10138-git-data-wipe-body/decision-challenges.md`.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; this one carries all three lines and the CPO sign-off.
- Every figure in this plan that came from an ADR or the design (volume ids, dates, byte sizes, site counts) is a claim to re-read at build time; the census numbers in Phase 5 are measured, never copied.
- The access census is Python embedded in bash: a row that greps a string the row's own description also contains is satisfied by its own text; use the executed-body and mutation rows.
- `env -i NAME=$value` is an argv leak (CTO 12b); the stdin handoff is the only allowed credential route to a child after the bridge or the loader.
- A skipped job's outputs are empty strings, and `'' != 'false'` is true: every notify clause pairs its own result check with its own `started` check.
- Do not push to this PR after it is armed or queued without asking.
