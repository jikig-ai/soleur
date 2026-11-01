---
title: "docs: git-data Record PR, real-flip run sheet (Ref #8211, #11704)"
type: docs
date: 2026-11-01
slug: git-data-record-pr-real-flip-run-sheet
branch: feat-one-shot-git-data-record-pr-runbook-run-sheet
issue: 8211
closes: none (Ref #8211, Ref #11704 only)
priority: p2-medium
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

## Overview

Docs-only Record PR named in the epic #8211 go-live plan comment (`issuecomment-6546561355`, "Record PR" item). The combined preconditions, overlay and success-signal PR (#11713, squash `78de558634`) merged and deployed on 2026-11-01; this PR records what that leaves for the first real flip.

It edits one file, `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`, and posts two GitHub comments:

1. Tick the "An ssh client in the web-platform image" precondition box, backed by a fresh read at the served build (CTO F4).
2. Rewrite the `#8209` precondition bullet as a dated status: OPEN, owner decision pending. No acceptance is written.
3. Add a `### Real-flip run sheet (#8211)` section (RF0 to RF9) mapping Phase B of the comment: pause ON during the flip, rollback only on a trigger, pause OFF after the go gate, canary steps, the R0 read list.
4. Comment on #11704: acceptance narrows to items 1 to 4, item 5 (the code comment in the hash-bound `git-data-transport-wrapper.sh`) is deferred to the later payload batch; cross-reference on #11433.

Hard constraints: no hash-bound rung-2 file is touched (list below), `Ref` never `Closes`, stop at a READY PR with required checks green, no auto-merge, no merge, no dispatch of `git-data-cutover.yml` or `apply-web-platform-infra.yml`, no `flip.sh`, no Doppler write, scoped tests only.

## Research Reconciliation: spec vs codebase

| Spec claim (brief / comment) | Reality (verified 2026-11-01) | Plan response |
|---|---|---|
| "Tick the ssh-client box: fact verified, startup lines on both hosts" | The runbook box says "on the deployed build". The Rehearsal 2 startup lines describe the image served 2026-10-31, not `78de558634`. | CTO F4: the tick cites a fresh read (one `git_data_ssh_client=present` row per host with host and UTC time, plus `/health` served sha), `--since` covering the `78de558634` deploy. If the read fails the box stays unticked and the record says why. |
| "#8209: no completion record for the three remaining rotations" | Confirmed: the newest #8209 comment is the CTO ruling of 2026-10-12; state OPEN, `updatedAt` 2026-10-12. Tier-B work (O1 to O13) is recorded in earlier comments. The runbook bullet still reads "(its own ADR)" with no status. | CTO F3: dated status bullet plus RF0 hard stop. The workflow only checks token presence (`precondition_8209_open`), so the sheet says it is not workflow-enforced. |
| "Split #11704 item 5 off its acceptance by commenting" | #11704 body: "Acceptance: items 1 to 5 ...". Its only comment (6553166477) is the triage bot, not the ruling. #11433 already tracks the hash-bound payload batch. | CTO F5: one comment on #11704, one cross-reference on #11433, no new issue, no body edit. Cite `issuecomment-6546561355`, not the triage comment. |
| Phase B step 5: "the canary session ends and the success marker is in Better Stack" | While the flag is on, `refs_assert` and `proof` refuse (`flag_already_true`, see "R3 first-session reading"). The positive evidence is the #11713 marker, read by `scripts/followthroughs/git-data-replication-signal.sh`, whose `MARKERS_PRESENT` means at least one replication, not per-user coverage. | RF5 names that script and its verdict words, and says what each non-pass verdict means. |
| Phase B step 6: "unset the exempt variable" | Unsetting it in Doppler does not change running containers (env fixed at `docker run`, comment in `apps/web-platform/server/quiet-window.ts`). | CTO F2: hygiene only; `exemptConfigured=true` afterwards is expected; no redeploy; verified through the Doppler name listing; the canary deletion at RF9 closes it. |
| "Add the R0 read list" | The rehearsal table already has an R0 row with the full read list and abort rules. | RF2 links to it and lists only what differs for the real flip. |
| Hash-bound file list "from the repo" | Not a static list: `git_data_rung2_bound_files` (in `tests/scripts/lib/git-data-birth-readiness-gate.sh`) derives it from the template and the module. Measured: 20 files (below). The runbook is not in the set. | Forbidden-file list below; AC1 recomputes it rather than trusting this copy. |
| Another PR may collide | Draft PR #10905 also edits this runbook, in three other hunks (the "Account request is refused by the store wrappers" paragraph, the "Neither is built" sentence of the Art. 17 rule, and the host-key step 5 sentence). #10901 does not touch it. | Keep this PR's edits to the four sites below; whichever PR merges second rebases. No shared lines. |

## Research Insights

**Premise validation (Phase 0.6).** Cited issues checked with `gh issue view`: #8211 OPEN, #11704 OPEN, #8209 OPEN, #11713 MERGED, #9066 OPEN, #11433 OPEN, #10296 OPEN, #10901 OPEN, #10905 OPEN, #10914 OPEN. Nothing cited as a blocker is already closed. Collision pre-check: open PRs naming #8211 are #10901 and #10905 (both the re-erasure path, not this change); two foreign `test-all.sh` processes belong to another worktree and are unrelated. The mechanism (run sheet in the existing runbook) was checked against the ADR corpus: ADR-068 and ADR-239 describe the cutover and neither rejects a runbook-resident run sheet; the rehearsal run sheet already lives in this file ("this section is the run sheet; it adds no mode and no dry run", CTO 2026-10-19).

**Property List (Phase 0.6b).**

1. The "ssh client" box reads ticked only when a fresh read at the served build shows it on both hosts.
2. The owner has one ordered sheet for the first real flip, with a hard-stop list, objective rollback triggers, and no step that needs a technical judgment mid-flip.
3. The #8209 position is unambiguous: OPEN, owner decision pending, nothing invented.
4. #11704's acceptance no longer depends on an edit to a hash-bound file.

**Cut List.** Separate runbook file for the sheet: cut (one file, existing pin tests and linter cover it; CTO F1). New committed test for the sheet: cut (the existing verdict-map, access and invocation-axis suites already read this file; AC commands check the new content once, a standing assertion on prose would pin wording, not behaviour). New tracking issue for item 5: cut (#11433 is the vehicle; CTO F5). Restating the R0 read list: cut (link). A `mode=redeploy` after the go gate: cut (CTO F2). Repeat rehearsal for pause-off: cut (CTO 2026-10-31: a canary session replaces it).

**Value-proposition measurement (Phase 0.6c).** No cost or performance claim is made.

**Hash-bound files this PR must not touch** (measured with `source tests/scripts/lib/git-data-birth-readiness-gate.sh; git_data_rung2_bound_files "$PWD/apps/web-platform/infra/cloud-init-git-data.yml"`, 20 files, all under `apps/web-platform/infra/`):

- `cloud-init-git-data.yml`
- `modules/git-data-userdata/main.tf`, `modules/git-data-userdata/outputs.tf`, `modules/git-data-userdata/variables.tf`
- `git-data-bootstrap.sh`, `git-data-pre-receive.sh`, `git-data-provision.sh`, `git-data-transport-wrapper.sh`, `git-data-remove.sh`
- `git-data-gc.sh`, `git-data-gc.service`, `git-data-gc-failure.service`, `git-data-gc.timer`
- `git-data-luks-reopen.sh`, `git-data-luks-reopen.service`, `git-data-luks-reopen-failure.service`, `git-data-luks-reopen.timer`
- `git-data-liveness.sh`, `git-data-liveness.service`, `git-data-liveness.timer`

Also not touched: `git-data-rung2-boot-evidence.env` (editing or deleting it voids the attestation; Guard 4 refuses a commit that touches it together with a bound file). The runbook, `rehearsal.tf` and the rung-2 workflow are not hash-bound.

**Doc-pin tests that read this runbook** (from repo research; headings are cited by name, zero `#anchor` links exist, so no existing heading is renamed or removed):

- `apps/web-platform/infra/git-data-refs-assert.test.sh`: needs `### Reading REFS-CONFIRMED` and `## Verdict map`.
- `apps/web-platform/infra/git-data-cutover-access.test.sh`: verdict-map row strings and `probe=… verdict=…` pairs.
- `apps/web-platform/infra/git-data-wipe-assert.test.sh`: the fenced block under "Literal pattern (" must equal the RE_34 regex byte for byte.
- `apps/web-platform/infra/git-data-wipe-access.test.sh`: every `wipe_*` word appears in the verdict map.
- `tests/scripts/test-git-data-root-key-arm.sh` and its gate lib: the remedy text names "Breach-triage trigger".
- `plugins/soleur/test/invocation-axis.test.ts`: exactly one line in this runbook names the skill `admin-ip-refresh`. The new section must not name it, nor any user-invoked skill.
- `scripts/lint-infra-no-human-steps.py` scans runbooks, plans and specs for human-actor plus infrastructure-imperative pairs; `hr-no-ssh-fallback-in-runbooks` forbids SSH reads. `scripts/markdown-lint.sh` (MD013 off; MD001 heading increment on).

**Institutional learnings applied.** A "ruled by X" citation is a claim to grep, write the decision row first (`2026-10-20-a-retried-failure-path-inherits-its-consumers-idempotency-and-a-cited-ruling-is-a-claim-to-grep.md`); a census must cover every parser of a governed file, here the shell suites that extract runbook blocks by name (`workflow-patterns/2026-10-29-shared-exemption-set-consumer-census-misses-untyped-parsers.md`); the typed-`yes` flip suites cannot run in an agent session, so the sheet marks every `flip.sh` step owner-run (`2026-10-23-an-update-arm-shipped-unexercised-because-every-stub-answered-200-and-the-typed-yes-suites-cannot-run-in-an-agent-session.md`).

## Scope Check

Ask mapping: tick ssh box (item 1), real-flip run sheet with the listed parts (item 3), #8209 position (item 2), #11704 item 5 split (item 4). Every Files-to-Edit entry maps to one of these. `inferred` items: the pointer lines in two existing sections (CTO F1) and the cross-reference comment on #11433 (CTO F5), both ruled. No split needed: one file, one comment pair.

## Implementation Phases

### Phase 0: read-only evidence (before any edit)

- 0.1 `git fetch origin main`; confirm `git log origin/main -- knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md` has nothing newer than this branch's base that touches the four edit sites; re-read #8209 (`gh issue view 8209 --json comments`) and note the newest comment date; re-read #11704 and #11433 state.
- 0.2 Deploy state: `bash plugins/soleur/scripts/deploy-arm.sh served 78de558634` and `find --wait` style read (read-only) and `/health`; record the served sha and version. If the served sha does not contain `78de558634`, stop the tick (F4) and say so.
- 0.3 Fresh read for the box tick (CTO F4): `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since <UTC time of the 78de558634 deploy> --grep git_data_ssh_client= --limit 50`, reduced to one row per host (host name, UTC time, value). Counts, host names and times only; no secret on a command line. If no row per host, leave the box unticked and record "not read" with the reason.
- 0.4 Recompute the hash-bound file list with `git_data_rung2_bound_files` and write it to the scratchpad for AC1.
- 0.5 Baseline the scoped tests on the unmodified tree (list in Phase 3) so a pre-existing red is not blamed on this PR.

### Phase 1: runbook edits (Edit tool, unique content anchors, one commit)

Four edit sites in `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`, anchored by content, not line number:

- **E1, the `#8209` bullet** (anchor: "**#8209** — evict the repo-secret-reachable credentials from `prd_terraform`"). Keep the leading text; add a dated status: "OPEN as of 2026-11-01." Tier-B eviction O1 to O13 recorded on #8209 (cite comment URLs read in 0.1); `HCLOUD_TOKEN`, `CF_API_TOKEN_R2` and `TF_STATE_AWS_*` each still need rotation with an old-value invalidation probe per the CTO ruling of 2026-10-12, with no completion record as of 2026-11-01; the outcome is the owner's (require the rotations, or record an acceptance of the residual) and this runbook records none; the workflow only checks `DOPPLER_TOKEN_INFRA_PRIVILEGED` is present (`precondition_8209_open`), so this is an RF0 hard stop held by the owner.
- **E2, the ssh-client box** (anchor: "**An ssh client in the web-platform image** (PR #9096)"). `- [ ]` to `- [x]` only if Phase 0.3 produced a row per host; append the dated evidence sentence (rows, host names, UTC times, served sha). Leave the rest of the bullet text unchanged.
- **E3, the new section** `### Real-flip run sheet (#8211)`, inserted after the "R3 first-session reading" paragraph and before `### The D6 rotate (dispatch BEFORE the flip)`. Content in the next subsection.
- **E4, two pointer lines**: one at the top of `### Before the first `flip`: the rollback rehearsal` ("the first real flip is sequenced in [Real-flip run sheet](#real-flip-run-sheet-8211)"), one bullet in `## After the real cutover (owned by #8211)`. Heading text of existing sections is not changed.

#### E3 content: Real-flip run sheet

Lead paragraph: "Ruled by CTO agent, 2026-10-31 and 2026-11-01 (#8211)". It links the existing "Authorization" paragraph of "Before the first `flip`: the rollback rehearsal" (every dispatch is its own owner-named command in the owner's own session; an agent reads, prepares and waits; no menu answer authorizes a step; dispatch on `main` only) instead of restating it, and states only the deltas: the pause is ON from before the flip until the go gate passes; rollback happens only on a trigger; a canary session before unpausing replaces a repeat pause-off rehearsal; `refs_assert` and `proof` refuse while the flag is on (`flag_already_true`), so the go gate reads the replication marker; merges and releases are held from RF2 to RF6 by discipline (there is no lever: the owner confirms the merge queue is empty and `deploy_in_flight` is clear); this Record PR merges before RF2 and the release workflow's path filter (`apps/web-platform/**`, `plugins/soleur/**`) excludes it, which the RF2 `deploy_in_flight` read confirms. The owner names a hold limit for RF1 to RF6 before RF1: while the pause is on real users' new sessions are refused. This sheet sets none (a schedule call).

Table with columns `Step | Kind | Command or read | Checks | A refusal or failure looks like`, Kind = R read-only, O owner-run production step, D owner-named dispatch.

| Step | Kind | Content |
|---|---|---|
| RF0 | R | Hard stops, one line each, with "workflow-enforced?" and a linked evidence line (issue comment URL or run id), never owner memory. #8209: see the Preconditions bullet (E1); not enforced. Per-id re-erasure path: #10901, then #10905 (after the CLO disclosure PR), then #10914 paging; not enforced; each merged and deployed. #9066 (lock files holding the user id): the CLO and owner call, fix first (a hash-bound payload change: two-PR sequence plus a paid rehearsal) or accept as residual; not enforced; accepting it as residual means an erasure can leave the user id on the store with no error signal (a silent shortfall), the CLO acceptance is on record before RF4, and a real-user erasure request received during the soak goes to the CLO (the Art. 12(3) one-month clock runs from the request). Art. 17 attestation for a real flip: CLO call; not enforced. The two unchecked boxes the runbook leaves to the owner (every merge-triggered apply `success`; the ssh client, ticked by E2). Heartbeats up and the merge queue empty: not workflow-enforced (the heartbeat control waits on #9943; `deploy_in_flight` covers release runs only). Enforced by the workflow: D6 stamp inside the 100-run window (`d6_replace_stale`; a stale stamp means stop, no rotate is dispatchable after a flag write (#10216), and the agent spawns the CTO), `pin_fault_paging_absent`, `pause_not_on` and `pause_unread`. Two owner decisions stay open, each needing a recorded decision comment URL before RF4: whether the R1 pause-off window (about 5 minutes) counts against the first-flip decision; whether the real flip waits past 2026-11-04. |
| RF1 | O | Before RF1 the owner prepares the canary account (the pause refuses repository setup for everyone except an exempt id, and the exemption loads only at the RF3 redeploy): create the Soleur-owned synthetic account, in no shared workspace, add its Claude credential, connect the throwaway repository (as in rehearsal 2), and verify the id is that account's, because a well-formed id that belongs to anyone else exempts them (see the exempt-account paragraph in the rehearsal rules). Then, owner, TTY: `bash plugins/soleur/skills/flag-set-role/scripts/flip.sh new-sessions-paused prd on` (also writes the Doppler mirror `FLAG_NEW_SESSIONS_PAUSED=1`). The pause stays on until RF6. |
| RF2 | R | Read-only R0: the rehearsal R0 row and its abort rules apply; this row lists only the real-flip deltas. Heartbeat read twice (the 15-minute bound is tight); two reporter rows per host at least 90 seconds apart reading `new_sessions_paused=1` and `agent_sessions_live=0`; `QUIET_WINDOW_EXEMPT_USER_ID` absent from the `prd` name listing; `WORKTREE_ROOT` name check; d6 index. Any red row means no dispatch. Abort before the flag write (RF1 to RF3: a red row, a failed redeploy, or the hold limit reached): the owner unsets `QUIET_WINDOW_EXEMPT_USER_ID` if it was set, then `flip.sh new-sessions-paused prd off`, and confirms the Doppler mirror reads 0. |
| RF3 | O | Canary setup, owner. Set `QUIET_WINDOW_EXEMPT_USER_ID` in Doppler `prd` to the verified id, then `gh workflow run git-data-cutover.yml --ref main -f mode=redeploy -f confirm=REDEPLOY-GIT-DATA` (about 75 s of web-1 restart); confirm `exemptConfigured=true` on both hosts. The redeploy restarts web-1: re-read the heartbeat, `deploy_in_flight` and the pause rows after it. |
| RF4 | D | Flip, owner-named: `gh workflow run git-data-cutover.yml --ref main -f mode=flip -f confirm=FLIP-GIT-DATA`, then the `web-platform-infra-apply` environment approval by the owner; read both hosts' control line immediately before and after the dispatch. Abort on any `new_sessions_paused=0` row, any live session, or a red flip step; the finalizer unwinds automatically. On a failed run follow "When a cutover run fails (the notify channel)" (`RECOVERY_FAILED` or `STATE UNKNOWN`: read the flag in `prd`, both hosts' `git_data_store=` lines and the sentinel first); the pause and the exemption stay in place while the owner decides, and the next attempt restarts at RF2. |
| RF5 | R then owner decides | Go/no-go, an agent reads and the owner decides. The canary session is started by the owner and ended by the owner (R3 row; the owner attests it ended). Reads: per-host `git_data_store=enabled`; `scripts/followthroughs/git-data-replication-signal.sh --since '<stamp>'`, where `<stamp>` is the earlier of the two per-host `enabled` readback times from the flip run log (not the cutover stamp), reads `MARKERS_PRESENT` (at least one replication, not per-user coverage, so the per-user R3 read still applies); zero replication `push failed`, `shed` or pin-fault rows; zero `worktree_lease` errors; zero `op:git-data-bare-repo-erasure` events; the `git-data-overlay-not-descendant` count and any level-50 `git-data-overlay` row read as the "Known latent behaviours" paragraph says. Each zero is read with proof its emitter is alive (the marker rate, the reporter rows and both git-data heartbeats in the same window): a zero from a dead emitter is unread, not green. `PENDING`, `NO_SESSIONS` and `READ_UNCLEAN` are unresolved, never a pass: re-read about every 10 minutes (the `PENDING` threshold) until the hold limit, then take the RF2 abort path or the pre-RF6 rollback of RF7. The canary's first-session overlay miss is expected and info-level since #11713. |
| RF6 | O | Owner: unset `QUIET_WINDOW_EXEMPT_USER_ID` in Doppler `prd`, verify only through the name listing; this is hygiene for the next deploy, because running containers keep the value until then, so `exemptConfigured=true` afterwards is expected and is not a failure or a trigger; no redeploy (it would lose unreplicated trees and the exemption is moot once the pause is off). Then `bash plugins/soleur/skills/flag-set-role/scripts/flip.sh new-sessions-paused prd off`; confirm the Doppler mirror reads 0. |
| RF7 | D, only on a trigger | Rollback, owner-named: `gh workflow run git-data-cutover.yml --ref main -f mode=rollback -f confirm=ROLLBACK-GIT-DATA`. Triggers: `ZERO_MARKERS_WITH_SESSIONS` on either host; any replication `push failed`, `shed` or pin-fault row; any `worktree_lease` error; any `op:git-data-bare-repo-erasure` event; a failed go gate (`git_data_store` not `enabled` while the flag is on). Not triggers: `PENDING`, `NO_SESSIONS`, a single `READ_UNCLEAN` (re-read, keep the pause on), the canary's expected overlay miss, `exemptConfigured=true` after the unset, unrelated Sentry noise, a web-2 log gap alone. Before RF6 (pause on, no real sessions) any trigger means rollback. After RF6 the first response is to re-pause (`flip.sh new-sessions-paused prd on`: cheap, reversible; it stops new sessions only and does nothing for sessions already live); rollback after RF6 is for the three data-integrity triggers only (erasure, push failed or shed or pin-fault, lease), and only once `agent_sessions_live=0` on both hosts (a dead reporter reads as unread, not zero) or the owner records an explicit decision to accept the loss of the live sessions' unreplicated work, with the count from the reporter rows; `ZERO_MARKERS_WITH_SESSIONS` or a failed go gate after RF6 means re-pause and investigate, and the owner decides on rollback after the drain. A re-pause ends only on the owner's decision after a clean re-read. Rollback sequence: unset the exemption before the dispatch (the rollback redeploy then clears it), R5 reads `disabled` on both hosts, pause OFF only after R5, R6 is `refs_assert` only (no deletion), R8 clears or records the stamp, and the backstop in "After the real cutover" applies (do not decommission the LUKS volume until git-data-only writes are reconciled). The owner is present to approve from the first dispatch (the rehearsal-2 rollback took 121 minutes, 89 of them the approval wait). |
| RF8 | R | Soak, 7 days: follow "After the real cutover (owned by #8211)" (soak script, replication-signal read, the rules and the Sentry sweep are listed there). One addition: any redeploy while the flag is on has the same loss exposure as a rollback, so a deploy or merge during the soak is done as re-pause, drain to `agent_sessions_live=0` on both hosts, deploy, then the owner decides to un-pause. |
| RF9 | O | Exit, each step owner-authorized: ADR-068 `adopting` to `accepted`; close #6897; delete the canary account (the first live Art. 17 erasure with the flag on, which also closes the exemption). `proof` and `refs_assert` refuse while the flag is on, so the evidence that the deletion worked is: the users and api_keys rows read empty, and zero `art17-erasure-incomplete` and `op:git-data-bare-repo-erasure` events; any such event goes to the CLO and the deletion is not repeated by hand. Do not `gh run delete` the three runs in #10216 before the 2026-12-29 re-baseline. No wipe modes to run (the plaintext volume is gone). Never rotate after the flip; break-glass only. |

No sentence in E3 tells a human to read or change a host over SSH; every read is a workflow annotation, a Better Stack query or a Sentry query.

### Phase 2: the two GitHub comments (after the commit is pushed, so the PR link resolves)

- #11704: one comment. Acceptance narrows to items 1 to 4 (item 3's runbook paragraph pointer stays); item 5 (the comment at about lines 104 to 105 of `apps/web-platform/infra/git-data-transport-wrapper.sh`) moves to the later hash-bound payload batch with #11433, #10296 and, if the CLO requires it, #9066; re-evaluate after the real-flip soak and an owner-scheduled rung-2 rehearsal; cite `issuecomment-6546561355` on #8211 (not the triage comment); link this PR. Text says `Ref #11704`; no closing keyword.
- #11433: posted after the #11704 comment so it can link it: one short cross-reference that item 5 of #11704 is batched here. `Ref #11433`.
- Record both comment URLs in the PR body. No new issue; no body edit on either issue.

### Phase 3: verification, push, PR

Scoped only. Never the unscoped full gate.

- `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` (the CI gate's own invocation, which scans the runbook, this plan, its tasks file and the decision table; an explicit-path run is not the gate). Also `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch` on the decision table (header exactly `| Item | Class | Ruling |`, every technical row starting `Ruled by CTO agent, <date>:`, no literal pipe inside a row).
- `bash scripts/markdown-lint.sh <runbook>`; heading-increment check.
- `bun test plugins/soleur/test/invocation-axis.test.ts` (from the repo root, plugin runner).
- `bash apps/web-platform/infra/git-data-refs-assert.test.sh`, `git-data-cutover-access.test.sh`, `git-data-wipe-assert.test.sh` (with the loopback env CI uses if it needs it), `git-data-wipe-access.test.sh`, and `bash tests/scripts/test-git-data-root-key-arm.sh`.
- Heading diff: `grep -nE '^#{1,4} '` on the runbook before and after; the only delta is the one new `###` heading.
- Secret scan before every push (the repo's secret-scan hook or script, whichever `plugins/soleur` documents); the diff carries counts, host names, times and run ids only.
- Commit with the trailer `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`; push; PR #11812 body: summary, `Ref #8211`, `Ref #11704`, the decision table from `decision-challenges.md`, the comment URLs, the session URL `https://claude.ai/code/session_018yoBtY15pXShUA8WFVwcne`, ending with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`. Mark ready; wait for required checks green; do not arm auto-merge; do not merge. Skip every merge and post-merge phase.

## Files to Edit

- `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md` (E1 to E4)

## Files to Create

- `knowledge-base/project/plans/2026-11-01-docs-git-data-record-pr-real-flip-run-sheet-plan.md` (this file)
- `knowledge-base/project/specs/feat-one-shot-git-data-record-pr-runbook-run-sheet/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-git-data-record-pr-runbook-run-sheet/decision-challenges.md`

No file under `apps/`, `plugins/`, `.github/`, `scripts/` or `tests/` is created or edited.

## Open Code-Review Overlap

None. Queried open `code-review` issues (200 limit) for the runbook path on 2026-11-01: no body names `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`.

## Acceptance Criteria

- AC1. `git diff --name-only origin/main...HEAD` lists only the runbook, the three planning artifacts, and the files the pipeline itself writes (`knowledge-base/INDEX.md` if regenerated, `knowledge-base/project/specs/feat-one-shot-git-data-record-pr-runbook-run-sheet/session-state.md` if present); its intersection with the recomputed `git_data_rung2_bound_files` output and with `apps/web-platform/infra/git-data-rung2-boot-evidence.env` is empty.
- AC2. The ssh box is `[x]` only with one `git_data_ssh_client=present` row per host (host, UTC time) and the served sha cited; otherwise it is `[ ]` and a sentence says the read was not made and why.
- AC3. The `#8209` bullet contains "OPEN as of 2026-11-01", names the three credentials, and `grep -niE 'accept(ed|ance)'` over the added lines matches only the conditional "or an acceptance comment ... written by the owner" form (no recorded acceptance).
- AC4. Exactly one `### Real-flip run sheet (#8211)` heading exists, between the "R3 first-session reading" paragraph and `### The D6 rotate`; rows RF0 to RF9 each appear once; RF1 prepares the canary account before the pause is turned on; RF2 has the abort-before-flag-write path; RF4 links "When a cutover run fails"; RF5 defines `<stamp>` and the re-read cadence; RF7 lists all five triggers and the non-triggers, the before-RF6 and after-RF6 actions and the post-rollback sequence; RF6 states that running containers keep the exemption until the next deploy; RF9 names the deletion evidence.
- AC4b. E3 carries the four CPO conditions: RF7 contains `agent_sessions_live=0` as the pre-rollback requirement; RF8 contains the drain check before any deploy; RF5 contains the emitter-alive pairing; RF0 contains "silent shortfall" for #9066 and "before RF4".
- AC5. No existing `#`-heading text changes (heading diff delta is one added line); the two pointer lines resolve to the new heading.
- AC6. The doc-pin suites, the linter, markdown-lint and the invocation-axis test pass; `admin-ip-refresh` still appears on exactly one line of the runbook.
- AC7. The #11704 and #11433 comments exist, cite `issuecomment-6546561355`, contain `Ref`, and neither contains `Closes`, `Fixes` or `Resolves`.
- AC8. The PR body has `Ref #8211`, `Ref #11704`, no closing keyword, the session URL, the decision table, and ends with the generated-with line; the commit trailer is present.
- AC9. PR #11812 is not a draft, all required checks are green, `gh pr view 11812 --json autoMergeRequest` is null, and the PR is not merged.
- AC10. The secret scan passes on every push, and no secret value appears in any added line, command line or comment.

## Test Scenarios

Docs-only; the standing suites in Phase 3 are the regression net. Each AC above has a one-line command in Phase 3 or is a `gh` read. The tick in AC2 is validated against live Better Stack data, not against the brief's statement (`hr-no-dashboard-eyeball-pull-data-yourself`).

## User-Brand Impact

**If this lands broken, the user experiences:** a real user's working tree (their only copy under `WORKTREE_ROOT`) is lost, or an Art. 17 erasure is silently refused, because the owner followed a run sheet whose order or triggers were wrong (for example rolling back with real sessions live, or unpausing before the go gate).
**If this leaks, the user's data is exposed via:** none new; the run sheet carries counts, host names, run ids and command names only. The canary account is cited by role, never by id.
**Brand-survival threshold:** single-user incident.

`requires_cpo_signoff: true` is set. CPO sign-off was requested at plan time (see Domain Review). `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** CTO ruled F1 to F6 and four missed forks (decision table). Core conclusions: the run sheet stays in this runbook as RF0 to RF9; unsetting the exempt variable does not reach running containers; the ssh tick needs a fresh read; #8209 is an RF0 hard stop recorded as OPEN; rollback has five objective triggers and, after the pause is off, re-pausing is the first response.

### Product (CPO)

**Status:** reviewed. SIGN-OFF WITH CONDITIONS for the single-user-incident threshold (2026-11-01). All four conditions change document text only and are folded into E3 above: (1) a rollback after RF6 needs `agent_sessions_live=0` on both hosts or a named owner decision, and a dead reporter reads as unread; (2) any redeploy with the flag on has the same loss exposure, so a drain check precedes any deploy or merge through the soak; (3) every RF5 zero is paired with proof its emitter is alive, and every not-enforced RF0 item ends in a linked evidence line; (4) accepting #9066 is stated as a silent Art. 17 shortfall, with the CLO acceptance on record before RF4 and a route for erasure requests received during the soak. The #8209 OPEN record and the #11704 split needed no change. No UI surface.

### Legal (CLO)

**Status:** not invoked. The PR makes no new legal claim: the Art. 17 text and CLO rulings it repeats are already in the runbook; the CLO calls (Art. 17 attestation, #9066, disclosure PR) are listed in RF0 as open and unanswered.

No GDPR gate trigger: no schema, migration, auth flow, API route or new processing activity. No IaC gate trigger: the owner-run flag flip and the Doppler variable are existing, documented owner-only production acts, not new provisioning. No observability, encryption-posture, ADR/C4 or guard-contract section applies (pure documentation; no architectural decision).

## Risks and Sharp Edges

- Pinned prose: a new line naming a user-invoked skill, or a changed verdict-map row, fails an existing suite; the section avoids both (AC6).
- A tick without a fresh read is the failure this plan exists to prevent; AC2 is conditional on the data, not on the brief.
- Do not restate the R0 read list; two copies drift. RF2 links.
- `MARKERS_PRESENT` can be satisfied by one synthetic account; the owner's go/no-go still needs the per-user read already in the runbook (R3). RF5 says so.
- The #8209 line must not read as a decision. The only place "acceptance" appears is as the owner's future act.
- Draft #10905 edits other hunks of the same file; rebase conflicts, if any, are textual and local.
- A plan whose `## User-Brand Impact` is empty fails `deepen-plan` Phase 4.6; this one carries concrete artifact, vector and threshold.

## Non-Goals

- No edit to any hash-bound payload, including item 5's code comment (deferred to the payload batch with #11433, #10296, #9066).
- No answer to the owner-only decisions: #8209 outcome, the pause-off window question, waiting past 2026-11-04, the CLO calls.
- No new test, no new issue, no ADR, no dispatch, no flag flip, no Doppler write.
