---
title: "fix: git-data rotate precondition must see repos replicated after the flip (#10175)"
type: fix
date: 2026-10-13
slug: git-data-rotate-post-flip-guard
branch: feat-one-shot-10175-git-data-rotate-post-flip-guard
issue: 10175
closes: 10175
lane: cross-domain
requires_cpo_signoff: true
---

# fix: git-data rotate precondition must see repos replicated after the flip (#10175)

Spec lacks valid lane: defaulted to cross-domain (fail-closed).

## Enhancement Summary

**Deepened on:** 2026-10-13
**Agents used:** soleur:engineering:cto (forks F1-F7), architecture-strategist, code-simplicity-reviewer, cpo, clo
**Key improvements:** scan reads every run attempt and defines "ran" (re-run and cancelled-job holes); d6 message made unconditional; post-flip break-glass and flip-prerequisite items from CPO/CLO; Observability section added; no-other-writer parity test.
**Open disagreement (operator may cut at review):** simplicity review would defer the boot_complete freshness layer and count cross-check; kept per CTO F3 and the operator's ask.

## Overview

The rotate precondition in the git-data replace job reads one boot-time row and so cannot tell a store that the flip has since populated. This plan adds a credential-free guard that refuses a rotate once any cutover run has attempted a flag write, adds a boot_complete freshness check as a second layer, amends the d6 failure text that steers the owner toward a rotate, and records the rule in the runbook. #9943 and #6975 are evaluated and left as scoped follow-ups.

## Research Insights

**Premise validation (Phase 0.6).** #10175 OPEN, #9943 OPEN, #6975 OPEN (read with `gh issue view`). The cited symbols exist on this branch: step `Rotate precondition — served store measured empty` (apply-web-platform-infra.yml, job `git_data_host_replace`), `git_data_served_empty_sql`/`git_data_served_empty_read` (scripts/lib/git-data-boot-signal-poll.sh), `scripts/lib/git-data-rotate-stamp.sh`. ADR corpus: ADR-239 Consequences records "keeps a prd token out of apply-web-platform-infra.yml" (a mechanism reading the Doppler flag in the replace job would reverse it); ADR-239 also fixes that rollback is flag-off only and data stays on LUKS. The issue's phrase "stamp older than the last recorded rollback" is contradicted by that: no rollback record exists (rollback does not clear GIT_DATA_LUKS_CUTOVER_AT, design-rollback-rehearsal.md F-D) and the store stays populated after a rollback.

**Property list (Phase 0.6b).**
1. A rotate cannot start once the LUKS store may have taken a write (flip or rollback attempted, even failed).
2. A stale boot-time row (from before the current host) cannot satisfy the emptiness precondition.
3. A failed refusal is loud and carries no bypass.
4. The d6 gate's own failure text never steers the owner to a rotate in a state where it destroys data.
5. The runbook states "never after the flip".

**Cut list.** (a) Reading `GIT_DATA_STORE_ENABLED` / `GIT_DATA_LUKS_CUTOVER_AT` from Doppler prd: buys property 1 but needs a prd token ADR-239 keeps out; run records already buy it. (b) Embedding the CF tunnel bridge + root key in the apply job for a live emptiness proof: widens the infra-privileged credential census; deferred (F4). (c) Stamp-based logic: the stamp survives a rollback, so it decides nothing. (d) A bypass or "reset" input: none, by design.

**Learnings applied.** Precedent for reading run records headlessly and failing closed on unreadable/in-flight: scripts/lib/git-data-rotate-stamp.sh (#10166/#10184). Step names are matched byte for byte by plugins/soleur/test/terraform-target-parity.test.ts, so the existing step `Rotate precondition — served store measured empty` keeps its exact name (it is the GDRS_PRECONDITION_STEP anchor).

**web-2 facts (read-only, from the repo).** web-2 exists in prd Terraform: `var.web_hosts` default in apps/web-platform/infra/variables.tf has `web-2` (hel1, 10.0.1.11, cpx22), an out-of-band standby (serving weight 0, ADR-143). It reads git-data only through the app's replication path (same shared `GIT_DATA_SSH_HOST_KEY` pin from Doppler prd, loaded by redeploy) and `web-git-data-probe` against 10.0.1.20:22, pinging the single unsuffixed `GIT_DATA_HEARTBEAT_URL` (web-probe-envwrite.sh; server.tf `git_data_probe_install` is hardcoded to web-1, web-2 receives the probe by cloud-init). The cutover needs no per-host step, no heartbeat suffix and no web-2 host-key pin: git-data-cutover.sh and git-data-flag-precheck.sh never reference web-2 (WEB_HOSTS defaults to web-1 as the jump host; the flip's per-host `git_data_store=` readback is the only per-host check and already covers both). The host-key pin (`web-2-ssh-host-key.pub`, #9151) is web-2's own SSH pin for Terraform provisioners, unrelated to git-data. The one real gap is #6975: a healthy web-1 probe masks a dead web-2-to-git-data path.

## Problem Statement

After the first real `flip`, `git-data-host-rotate` passes its precondition (the newest `stage=boot_complete` row still says `served_repos=0`, emitted once per boot) and the plan gate accepts the exact `["delete","create"]` for `hcloud_volume.git_data_luks`; the plaintext volume is empty by construction, so the rotate destroys the only copy. `confirm=ROTATE-GIT-DATA` is a typo guard. The d6 failure text additionally tells the owner to dispatch that rotate. Latent today (flag never true); live at the first flip.

## Proposed Solution

Rulings in `knowledge-base/project/specs/feat-one-shot-10175-git-data-rotate-post-flip-guard/decision-challenges.md` (CTO, 2026-10-13).

1. **New step, before the existing precondition: `Rotate precondition — store never written (cutover run records)`** (apply-web-platform-infra.yml, job `git_data_host_replace`, `if: inputs.apply_target == 'git-data-host-rotate'`). It sources a new library `scripts/lib/git-data-store-dirty-scan.sh` and refuses unless the verdict is `store_clean`. The job gets job-level `permissions: contents: read, actions: read` and the step binds `GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}` (only this step). No prd token.
2. **Scan semantics** (`git_data_store_dirty_scan`, reads `<run id><TAB><status>` newest-first on stdin, like `git_data_d6_scan`): for each run of `git-data-cutover.yml` (ALL runs, no `status`/`branch`/`actor` filter because filtered listings hit the 1000-result cap, full pagination via `gh api --paginate`, collected count cross-checked against `total_count`; an API error or a count mismatch is `scan_unreadable`) and for EVERY attempt of that run (`run_attempt` 1..n via `/actions/runs/{id}/attempts/{n}/jobs`; `gh run view --json jobs` returns only the latest attempt, so a re-run that reaches resume arm B or `nothing_to_rollback` would otherwise hide the first attempt's flag write — architecture review, blocking), read the `cutover` job's step `Write GIT_DATA_STORE_ENABLED (via the #8573 seam)`: `skipped` or no `cutover` job started (mode proof/unfreeze/redeploy, `nothing_to_rollback`, resume arm B, confirm rejected) is clean for that run; ANY other conclusion (success, failure, cancelled, null/unknown on a listed step) is `store_dirty <id>`; a job "ran" only if it has a non-empty `steps` array or a non-null `started_at`; a `cutover` job with empty steps and conclusion `cancelled`/`skipped` (cancelled while queued, approval rejected) is clean, and an absent write step on a job that ran is `scan_unreadable <id>` (rename drift fails closed). Zero runs with `total_count == 0` is `store_clean` (a never-flipped store); the workflow file name `git-data-cutover.yml` is pinned by the parity test alongside the step literal; `status=in_progress` is `cutover_in_flight <id>`; queued/waiting/pending runs have executed nothing and are skipped (the shared `git-data-state` concurrency group means one cannot overlap this job). Verdict tokens: `store_clean | store_dirty <id> | cutover_in_flight <id> | scan_unreadable [<id>]`; returns 0 only for `store_clean`. The decision uses neither the stamp nor the flag value (F2).
3. **Second layer: boot_complete freshness.** New sibling query `git_data_boot_complete_dt_sql` + `git_data_boot_complete_dt_read` in scripts/lib/git-data-boot-signal-poll.sh (same pins, `--only-secrets`, absolute-path refusals) returning the newest `boot_complete` epoch seconds; `git_data_served_empty_sql` is NOT changed. The job reads the current server's `created` from the Hetzner API (`GET /v1/servers?name=soleur-git-data`, `bc_curl` stdin-config form, `HCLOUD_TOKEN` already loader-exported) and the existing step additionally requires `boot_complete_epoch > created_epoch` (strict). Zero or more than one server, a missing/unparseable `created`, or a missing timestamp refuse. A stale row from before the current host reads `stale_boot_complete`.
4. **d6 text (F7, made unconditional per the architecture review).** In git-data-cutover.yml step `flip_preconditions`, the `d6_replace_stale` message no longer carries a bare dispatch instruction: it says a rotate is required before the first flip only, that the rotate is guarded and refused once any flip/rollback was attempted (it would destroy the only copy), gives the dispatch command only as "on a never-flipped store", names the runbook break-glass section, and states there is no bypass input and escalation targets (#10175, #8571). Pinned in the cutover workflow test that already matches the message.
5. **Runbook (`git-data-luks-cutover-5274.md`).** D6 rotate section: a leading "Never dispatch the rotate after the flip, or after any flip/rollback attempt (including a rehearsal): the store may hold the only copy of replicated repositories; the guard refuses it and there is no bypass input"; a verdict table for the new refusals (`store_dirty`, `cutover_in_flight`, `scan_unreadable`, `stale_boot_complete`, `boot_complete_unreadable`); the existing `served_repos=0` paragraph corrected to say it is a once-per-boot reading and not a live proof; one sentence that the web-fed heartbeat is not a flip precondition (so #6975 does not block); the follow-up notes below.
6. **Follow-ups filed, not built:** F4 (mode-unique "store measured empty" marker in git-data-cutover.yml, the later live proof and exit from dirty; blocked on #8571 for a populated store), #9943 (left open, merged design; flip precondition in a different workflow), #6975 (left open; Terraform fan-out). Each gets a GitHub issue or an existing-issue comment at work time with re-evaluation criteria and milestone from knowledge-base/product/roadmap.md.

7. **Post-flip rotate need (CPO conditions 1-4, CLO).** The guard is a floor against the accidental dispatch, not a prohibition on ever rotating. The runbook gains a section "When a rotate is needed after the flip" that states: (a) the workflow offers no bypass input (CTO F7); (b) a suspected `GIT_DATA_LUKS_KEY` compromise (including Doppler secret exposure) is an owner-run break-glass, not a workflow dispatch: contain first (revoke secret access, detach the volume per the existing host-incident procedure), then the replicas are re-seeded from the web hosts (git-data is a replica; the runbook already records that it self-heals at each workspace's next session end by force-pushing every head and tag), then a reviewed PR that lifts the guard for one dispatch with the owner and CLO named as reviewers, then the rotate; containment within hours, re-encryption within days, Art. 33's 72 hours counted from awareness; (c) the ordinary Art. 17 residue (erased means unlinked, ADR-239) is accepted until #8571 lands, with a dated re-evaluation: the date is set by the owner at work time, with the CLO re-opened if it is missed (the ADR-239 2026-10-22 pattern); (d) "escalate" names its targets: issue #10175 for the guard and issue #8571 for copy mode, plus the owner. A PA-36 (g)(2) cross-reference ("rotation is deferred by the #10175 guard") is added to the ADR-239 amendment trail only (no legal document is edited); the compliance-posture entry for the residue window is a follow-up for the CLO, filed at work time.
8. **Flip prerequisite (CPO condition 2).** F4 (the "store measured empty" marker) and #8571 get a milestone from knowledge-base/product/roadmap.md and a re-evaluation trigger: "the first real `mode=flip` is booked". The runbook's Preconditions-for-the-flip list gains one item: owner has recorded acceptance that no post-flip rotate route exists until #8571 or F4 lands, naming the break-glass above. The roadmap is not edited by this plan (fog goes to the roadmap workshop); the item lives in the runbook and the filed issues.

## Technical Considerations

- **Residual risks, stated in the runbook and recorded as accepted by the owner (CPO condition 5):** run records deleted by hand, and a flag set outside the workflow, are invisible to the scan (the boot_complete freshness layer and the typed-token/approval gate remain). The guard is a floor for the accidental dispatch, not a defence against a hostile owner.
- **Ordering:** both new refusals sit before the rung-2 interlock and the plan gate, so the destructive plan is never reached on a dirty store; they run under the `git-data-state` group already held by the job (TOCTOU with a flip is closed by the group).
- **No other writer:** a parity test fails if any other workflow or script runs `doppler secrets set GIT_DATA_STORE_ENABLED` besides the cutover write step, the finalizer and flag-precheck's write arm (only `git-data-cutover.yml` and `git-data-flag-precheck.sh` today).
- **Plan-only:** a `plan_only=true` rotate is also refused on a dirty store; that is intended (the new step carries `if: apply_target == rotate`, not a plan_only condition, so it is not a census G5c step and must not be mistaken for one).
- **d6 interaction (architecture review):** `d6_replace_stale` also fires when the rotate marker run ages out of the 100 newest dispatch runs; on a flipped-then-rolled-back store the flip's own D6 precondition would then demand the rotate this guard forbids. The d6 message is therefore made UNCONDITIONAL (it never instructs a rotate; it says the rotate precondition is guarded and names the break-glass section), and the runbook states the deadlock and files a follow-up for a durable rotate stamp.
- **Credential census:** `actions: read` is job-level and pinned in tests/scripts/test-infra-privileged-tier-census.sh; no `secrets.*` beyond GITHUB_TOKEN is added; no step gains `if: plan_only` interplay (the new step is a gate step and stays unconditional on plan_only like the census G5c class).
- **d6 interaction:** the new step is a separate name; `GDRS_PRECONDITION_STEP` stays intact. A rotate refused by the new step skips the precondition step, which the stamp library reads as `skip` (nothing mutated), unchanged semantics.
- **NFR/ADR:** no new architectural decision (a refusal on an existing path; ADR-239's no-prd-token stance is preserved); no ADR or C4 change. No data model change.

## Files to Edit

- `.github/workflows/apply-web-platform-infra.yml` (job-level permissions; new step; freshness addition to the existing step)
- `.github/workflows/git-data-cutover.yml` (d6_replace_stale message only)
- `scripts/lib/git-data-boot-signal-poll.sh` (new dt sql/read functions; existing ones untouched)
- `plugins/soleur/test/terraform-target-parity.test.ts` (pin the new step, permissions, order, no-bypass)
- `tests/scripts/test-git-data-boot-signal-poll.sh` (new dt read rows)
- `tests/scripts/test-infra-privileged-tier-census.sh` (pin job-level `actions: read` for this job)
- the cutover workflow test that pins the d6 message (locate with `grep -rn d6_replace_stale tests apps/web-platform/infra plugins/soleur/test`)
- `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`

## Files to Create

- `scripts/lib/git-data-store-dirty-scan.sh` (sourced library; no `exit`)
- `scripts/lib/git-data-store-dirty-scan.test.sh` (synthesized jq fixtures, `gh` shim, mutation battery; register by presence per scripts/suite-shard-legs.tsv convention)

## Open Code-Review Overlap

To run at work time (`gh issue list --label code-review`); none identified during planning.

## User-Brand Impact

- **If this lands broken, the user experiences:** a rotate that either destroys their only replicated repository copy (guard fails open) or an unrunnable rotate that blocks the flip's required D6 step (guard fails closed on a clean store).
- **If this leaks, the user's data is exposed via:** no new exposure vector: no new credential, no secret printed, run records read with a read-only token.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** the failure destroys user repositories irrecoverably, so single-user incident rather than aggregate pattern. CPO sign-off required before `soleur:work`; `soleur:engineering:review:user-impact-reviewer` runs at review.

## Observability

```yaml
liveness_signal:
  what: the guard is a dispatch-time gate with no standing process; its signal is the refusal itself (an `::error` annotation naming the verdict token) on every rotate dispatch, plus the existing git-data host heartbeat soleur-git-data-host-prd (ADR-283) for the host
  cadence: per rotate dispatch
  alert_target: the dispatching operator via the failed run; no page (a refusal is the intended outcome)
  configured_in: .github/workflows/apply-web-platform-infra.yml (step "Rotate precondition — store never written (cutover run records)")

error_reporting:
  destination: GitHub Actions run annotations (`::error::`) carrying a fixed verdict word; no secret, run ids and counts only
  fail_loud: exit 1 with verdict store_dirty | cutover_in_flight | scan_unreadable | stale_boot_complete | boot_complete_unreadable

failure_modes:
  - mode: guard fails open (a flag-writing run is not counted: renamed step, deleted run records, a second workflow)
    detection: parity test pins the step literal in both git-data-cutover.yml and the scan library; scan returns scan_unreadable on a count mismatch or an absent step on a job that ran
    alert_route: CI red on the PR that renames the step
  - mode: guard fails closed on a clean store (API or pagination error)
    detection: scan_unreadable annotation with the failing run id
    alert_route: operator re-dispatches; no bypass exists by design
  - mode: stale boot_complete row accepted
    detection: strict created-versus-row comparison, tested at equality and one second before
    alert_route: stale_boot_complete refusal

logs:
  where: GitHub Actions run log of apply-web-platform-infra.yml
  retention: GitHub default run-log retention (90 days); the verdict word is also readable from the run's job and step conclusions via the API

discoverability_test:
  command: grep -c "Rotate precondition — store never written (cutover run records)" .github/workflows/apply-web-platform-infra.yml
  expected_output: "1"
```

## Guard Contract

### Guard 1 — store-never-written scan

**Property.** A `git-data-host-rotate` dispatch proceeds only if no run of git-data-cutover.yml has ever executed the flag-write step, and refuses on any run it cannot read.

**Assembly.** Quantifies over every run of git-data-cutover.yml (full pagination, count cross-checked) and, per run, every job named `cutover` and the one step `Write GIT_DATA_STORE_ENABLED (via the #8573 seam)`; the single chokepoint is `git_data_store_dirty_scan` called by exactly one step of `git_data_host_replace`; flip and rollback both flow through that one step name in git-data-cutover.yml. A second call site, a second step name for the flag write, or a first-page-only read are the defects.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Fixture: newest run clean, an older run with the write step `success` | RED (store_dirty names the older id) |
| 2 | Empty stdin / zero runs listed but `total_count` > 0 (the guard's own dispatch checking nothing) | RED (scan_unreadable) |
| 3 | A second dirty run after a compliant first (clean, clean, failure-conclusion write step) | RED |
| 4 | Write step `cancelled` / null conclusion | RED (any non-skipped is dirty) |
| 5 | Step renamed (absent) on a job that ran | RED (scan_unreadable) |
| 6 | Library edited so the loop `return`s clean at the first clean run | RED via row 3 |
| 7 | Workflow reorder: new step placed after the plan step | RED (parity test order pin) |
| 8 | Re-run fixture: attempt 1 has the write step `success`, attempt 2 (latest) has it `skipped` | RED (store_dirty; every attempt is read) |
| 9 | A `cutover` job with empty steps and conclusion `cancelled` among otherwise clean runs | clean (must-PASS, no permanent deadlock) |
| 10 | Second workflow script gains `doppler secrets set GIT_DATA_STORE_ENABLED` | RED (no-other-writer parity test) |

Harness rows: a suite whose success is `fail == 0` with zero rows run must exit non-zero (row-count floor); must-PASS fixtures that are not the canonical (resume-arm-B run with write step `skipped`, a `mode=proof` run with the proof step but no write step, a never-flipped history of only proofs) must yield `store_clean`; the `gh` shim refuses any argv outside the expected two shapes and an epilogue row asserts it never refused. Anchor: the scanned step name is a string in two files; the parity test asserts the same literal appears in git-data-cutover.yml and the library, so a rename on one side reds a test rather than a flip.

### Guard 2 — boot_complete freshness

**Property.** A `boot_complete` row older than the current git-data server's creation cannot discharge the emptiness precondition.

**Assembly.** The single comparison in the existing precondition step; inputs: `git_data_boot_complete_dt_read` (pinned git-data tables) and the Hetzner `created` of the one server named soleur-git-data.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | boot_complete epoch one second before `created` | RED |
| 2 | boot_complete epoch equal to `created` (strictness) | RED |
| 3 | Two servers returned by the API, second one stale | RED (refuse on count != 1) |
| 4 | Empty read output (the guard's own dispatch) | RED (unreadable, fail closed) |

Harness rows: must-PASS with epoch = created + 1 and with a different JSON key order in the API body.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "refuse the rotate unless the flag GIT_DATA_STORE_ENABLED is not true, the GIT_DATA_LUKS_CUTOVER_AT stamp is absent (or older than the last recorded rollback), and the boot_complete row is newer than the current server's creation time" | Proposed Solution 1-3 (flag/stamp replaced by run-record evidence, F1/F2) | mapped |
| 2 | "add a live emptiness proof through the cutover bridge if feasible" | Proposed Solution 6 (infeasible without widening the census; follow-up, F4) | descoped — justification: embedding bridge + root key in the infra-privileged job widens the credential census |
| 3 | "update the runbook D6 rotate section (\"never after the flip\")" | Proposed Solution 5 | mapped |
| 4 | "evaluate #9943 ... and #6975 ... include them only if they are flip preconditions or small and cohesive; otherwise leave a clearly scoped follow-up note" | Proposed Solution 6; decision-challenges F5/F6 | mapped |
| 5 | "Also report ... web-2" | Research Insights (web-2 facts) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| New run-record step + library | "refuse the rotate unless the flag GIT_DATA_STORE_ENABLED is not true" | asked |
| boot_complete freshness | "the boot_complete row is newer than the current server's creation time" | asked |
| d6 message amendment | "update the runbook D6 rotate section" (the d6 failure text is the same hazard, per design-wipe-body-pr.md) | inferred — justification: one-line message that otherwise tells the owner to dispatch the destructive rotate; CTO F7 |
| Runbook verdict table | "update the runbook D6 rotate section" | asked |

### Split Assessment

- Subsystems touched: 3 — .github/workflows, scripts/lib (+tests), knowledge-base runbook
- Planned files: 11 | Estimated changed lines: ~450 (library ~90, tests ~200, workflow ~60, runbook ~60)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] `git-data-host-rotate` is refused by a new step before the plan gate when any git-data-cutover.yml run has a non-skipped `Write GIT_DATA_STORE_ENABLED (via the #8573 seam)` step (scripts/lib/git-data-store-dirty-scan.sh; apply-web-platform-infra.yml step `Rotate precondition — store never written (cutover run records)`).
- [ ] The scan reads every attempt of every run (re-run fixture RED) and treats an empty-steps cancelled job as clean.
- [ ] A scan that cannot read every run, finds a count mismatch, or hits a renamed step refuses; there is no bypass input and no `continue-on-error` on the step (parity test).
- [ ] The existing `served_repos=0` step also requires boot_complete strictly newer than the single `soleur-git-data` server's `created`; `git_data_served_empty_sql` is byte-unchanged.
- [ ] Job-level `permissions` is exactly `contents: read` + `actions: read` and the census test pins it; no new secret is bound.
- [ ] The `d6_replace_stale` message is unconditional (it no longer instructs a rotate; it names the guard, the break-glass section and #10175/#8571 as escalation targets, and says no bypass input); its test pin is updated.
- [ ] Runbook D6 section carries "never after the flip", the verdict table, the corrected `served_repos=0` paragraph, the web-fed-heartbeat sentence and the follow-up notes; markdownlint passes.
- [ ] Follow-up issues/notes exist for F4, #9943 and #6975 with re-evaluation criteria; F4/#8571 carry a milestone and a flip-booked trigger.
- [ ] Runbook has the "When a rotate is needed after the flip" section (break-glass for key compromise, Art. 17 residue acceptance with a dated re-evaluation, named escalation targets) and the flip-precondition item.
- [ ] A test pins that the census is unchanged except the job-level `actions: read` (no new secret bound to the job).
- [ ] `git-data-store-dirty-scan.test.sh` runs the full mutation matrix, harness rows and a row-count floor green; existing `tests/scripts/test-git-data-boot-signal-poll.sh`, `git-data-rotate-stamp.test.sh`, terraform-target-parity and census suites stay green.
- [ ] No workflow dispatched, no terraform apply, no production write (verify by the PR diff and run history).

## Test Scenarios

- Given only mode=proof runs and skipped write steps, when a rotate is dispatched, then `store_clean` (unit).
- Given a flip run whose write step succeeded then a rollback, when a rotate is dispatched, then `store_dirty` (unit; regression for the issue's own "older than last rollback" wording).
- Given a flip that failed after the write, then `store_dirty` (unit).
- Given `gh api` failure or truncated pagination, then `scan_unreadable` and the step exits 1 (unit).
- Given boot_complete older than the server `created`, then refusal (unit).
- Given the workflow file, then the new step precedes the rung-2 interlock and plan step, binds only GH_TOKEN, and has no `continue-on-error` or input-driven bypass (integration, terraform-target-parity).
- Verification (read-only, no dispatch): `bash scripts/lib/git-data-store-dirty-scan.test.sh` and `bash tests/scripts/test-git-data-boot-signal-poll.sh`.

## Dependencies & Risks

- Risk: GitHub API pagination or retention hides old runs (fail closed on count mismatch; residual for hand-deleted runs).
- Risk: `HCLOUD_TOKEN` may be absent in this job under a legacy credential path (fails closed with a named message; verify at work time against .github/actions/infra-credentials).
- Risk: the cutover workflow edit carries the no-admin-merge restriction; message-only change.
- Dependency: none blocking; #8571 is the future exit for a populated store.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails deepen-plan Phase 4.6; this one is filled.
- Do not rename `Rotate precondition — served store measured empty`; the stamp library and parity test match it byte for byte (em dash U+2014).
- The scan must not key on the stamp or the flag value (F2): the stamp survives a rollback.
