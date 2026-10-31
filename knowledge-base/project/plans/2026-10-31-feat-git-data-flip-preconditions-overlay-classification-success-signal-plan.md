---
title: "git-data go-live Phase A: flip pause precondition, first-session overlay classification and ancestry guard, replication-success signal"
date: 2026-10-31
slug: git-data-flip-preconditions-overlay-classification-success-signal
branch: feat-one-shot-git-data-flip-preconditions-overlay-success-signal
issue: 11704
type: feat
lane: single-domain
requires_cpo_signoff: true
brand_survival_threshold: single-user incident
---

## Enhancement Summary

**Deepened on:** 2026-10-31
**Sections enhanced:** Scope Check (made schema-compliant), Research Insights (verification record), C4 citation.
**Reviewers and rulings already folded in before this pass:** CTO rounds 1 and 2 (F1 to F11), CPO sign-off, and a five-agent plan review (DHH, Kieran, code-simplicity, architecture, spec-flow).

### Key improvements carried by the plan
1. The ancestry skip is only shipped together with a rescue branch, because the session-end force-push would otherwise destroy the only copy of replicated-only commits.
2. The pause gate fails closed on stale rows (newest row at most 75 s old), never receives raw log rows (integers extracted in SQL), and binds its Better Stack credential per command.
3. The zero-markers read is per host with a worst-of aggregate, and only `MARKERS_PRESENT` is positive evidence.

### New considerations discovered in this pass
- The SQL of the pause gate and of the signal read cannot be validated offline; both get a live read-only dry run first (learning of 2026-10-19).
- `git-data-cutover-access.test.sh` carries two anti-vacuity floors (`FLOOR`, `MUTANT_FLOOR`) and a workflow-verdict count pin that all move with the new rows.

## Overview

One pull request (draft PR #11713) that carries the three Phase A changes of the CTO go-live plan on #8211 (comment 6546561355), referencing #11704 and #8211 with `Ref` only. Neither issue is closed by this PR.

- **A. Flip pause precondition.** The `Flip preconditions` step of `.github/workflows/git-data-cutover.yml` refuses unless both web hosts report `new_sessions_paused=1` in every row of the last 2 minutes, with the newest row at most 75 s old, before the SSH bridge is reached (so before any host is touched).
- **B. First-session overlay classification and ancestry guard.** The expected first-session store miss (`does not exist (provision it first)`, exit 128) stops being a level-50 `silent fallback`; the session-start overlay `reset --hard` runs only when the store tip descends from the fresh clone tip, and when it does not, the store tip is first preserved on a local rescue branch so the next replication push cannot make it unreachable; a real-git characterization test pins what a stale-clone force-push can and cannot do against the real fence hook.
- **C. Replication-success signal.** A warn-level, counts-only marker on a successful replication push reaches Better Stack, with an owner-run read for "zero markers while sessions are live", and the runbook's "R3 first-session reading" paragraph points at it.

Hard constraints carried from the brief: no hash-bound file is touched (the bound set is `cloud-init-git-data.yml` plus every `file()` payload in `apps/web-platform/infra/modules/git-data-userdata/main.tf`, which includes `git-data-pre-receive.sh`, `git-data-transport-wrapper.sh`, `git-data-provision.sh`, `git-data-remove.sh`, `git-data-bootstrap.sh`, `git-data-gc*`, `git-data-luks-reopen*` and `git-data-liveness*`); the wrapper comment (#11704 item 5) is not touched; no workflow dispatch, no `flip.sh`, no Doppler write, no merge, no auto-merge. The PR stops at ready with checks green.

## Research Reconciliation — Spec vs. Codebase

| Spec / brief claim | Reality (verified on origin/main `ba483a9948`) | Plan response |
|---|---|---|
| "read the per-host reporter line from Better Stack" | The reporter is `startQuietWindowReporter` (`apps/web-platform/server/quiet-window.ts`), a warn-level pino line once a minute per host: `agent_sessions_live=N cc_queries=N legacy_sessions=N starting=N new_sessions_paused=<0\|1> refused_since_last=N`. Better Stack rows are double-encoded JSON (`raw` is a JSON string). The workflow already reads Better Stack in its `Per-host git_data_store= assertion` step with `doppler run --preserve-env -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh` and the host pair `soleur-web-platform soleur-inngest-prd` (web-1) / `soleur-web-2` (web-2). | Reuse that read pattern and host pair. Extract integers in SQL behind a full closed-grammar `match` so the runner never receives raw rows (CTO F9). |
| "refusing before any host is touched" | `flip_preconditions` precedes `CF Tunnel SSH bridge`, key fetch and ssh_config in step order (pinned by suite row D-6). | Add the check inside `flip_preconditions`, last, so no new step ordering is needed. |
| Issue #11704 item 1 says `newSessionsPaused=true` (structured field) | The grammar line uses `new_sessions_paused=<0\|1>`; the CTO plan and runbook use the grammar form. | Read the grammar form. |
| "classify ... `does not exist (provision it first)`, exit 128 as info" | The stderr comes from the bound transport wrapper (`reject "repo does not exist (provision it first): '<path>'"`, relayed as `remote: git-data transport: ...`) through ssh, then git exits 128 with `fatal: Could not read from remote repository.`. `gitWithPrivateKeyAuth` does not catch or wrap: the rejection is the raw `execFile` error (`.code` numeric, `.stderr`, `.message`). The stderr carries the bare-repo path (which names the workspace id). The store repository is created by the session-end provision that precedes the replication push (`provisionGitDataRepo`), so a missing store repository self-heals at the first session end and the push itself never meets this error. | Match numeric `code === 128` plus the phrase on `err.stderr` (fallback `err.message`); the info log carries none of path, repo name or user id; prove the matcher against the real thrown shape. |
| "overlay `reset --hard` only when the store tip descends from the clone tip" | `ensure-workspace-repo.ts` resets unconditionally when `refs/remotes/git-data/<primary>` exists. The workspace clone is `--depth 1` and the store is shallow, so a shallow boundary cuts the parent link: `--is-ancestor <store> HEAD` cannot prove "store is behind the clone" (Kieran P1). `show-ref` failures of any kind currently read as "ref absent" (pre-existing masking; unchanged). | Gate the reset with `git merge-base --is-ancestor HEAD <dataRef>` under the workspace lock: exit 0 resets, exit 1 skips as one reason `not_descendant`, any other exit falls into the level-50 catch. The skip is only safe with a rescue branch (below). |
| (implicit) a skip is the safe direction | Not by itself (architecture review P1): the session-end push force-overwrites the user's own namespace from `refs/heads/*`, so after a skip the next push would destroy the only copy of replicated-only commits, which the old unconditional reset used to keep. | Before every skip create local branch `soleur/store-tip-<12 hex>` at the fetched store tip (CTO F7/F11); the next `refs/heads/*` push carries those commits into the store as a head. Failure to create it falls into the level-50 catch and the reset path never runs. |
| "stale-clone push stays confined to the user's own namespace and the lease fence rejects it" | `git-data-pre-receive.sh` enforces `refs/soleur/worktrees/<id>/` ownership and a strict `<` lease-gen reject. Two shapes differ: a stale GENERATION is rejected; a stale CLONE holding the CURRENT generation is accepted and `--force` overwrites its own namespace tip. | The characterization test pins cross-namespace reject, stale-gen reject and the same-gen own-namespace overwrite, labelling the last an accepted, tracked residual (#11716). If any cross-namespace overwrite is observed, stop and report. |
| "warn-level, counts-only marker" | `log.info("git-data replication push complete", {workspaceIdHash, worktreeIdHash, leaseGeneration})` is info (never ships) and carries hashes. Warn rows ship; a pino warn is a Sentry breadcrumb only, not an event. | Add a separate warn line with only integers and bits; leave the info line untouched. |
| "a Better Stack read or alert definition" | A Better Stack alert or a new scheduled workflow is a production-infra change (apply path forbidden for this task). Precedent for an owner-run read-only collector: `scripts/followthroughs/git-data-rehearsal-evidence.sh`. | Ship a read script under `scripts/followthroughs/` with an offline test; no alert, no workflow, no Terraform. |
| #8211 plan comment: "A, B, C in one PR" | Open PR #10928 also edits `git-data-cutover.yml` (different step); drafts #10901 and #10905 touch the runbook in other regions. | Keep the workflow and runbook edits localized; rebase conflicts are mechanical. |

## Premise Validation

Checked 2026-10-31: #11704 and #8211 are open (not stale). Cited files exist on origin/main: `.github/workflows/git-data-cutover.yml` (step `flip_preconditions`), `apps/web-platform/server/ensure-workspace-repo.ts`, `apps/web-platform/server/git-data-replication.ts`, `apps/web-platform/server/quiet-window.ts`, `apps/web-platform/infra/git-data-pre-receive.sh`, runbook `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md` (paragraph "R3 first-session reading" present). ADR corpus: ADR-068 (multi-host workspaces, lease coordinator) governs; `git-data-client.ts` says "the fence, not ref ancestry, is the ordering authority" for WRITES, which this plan leaves intact (the ancestry gate is read-side; the rescue branch feeds the write's content, which the ADR addendum states). No ADR rejects a read-side ancestry guard. Collision pre-check: no open PR names #11704; #10901/#10905 name #8211 (re-erasure path, disjoint files except the runbook); foreign `test-all.sh` processes belong to another worktree. Environment note: the worktree directory was removed by an external cleanup mid-planning and re-created on the same branch; everything below was re-written from the session record.

## Research Insights

**Property List**

1. The flip cannot start while a real user could start a store-enabled session: both hosts must show the pause on in fresh rows, otherwise the dispatch refuses before touching any host.
2. A flip refusal names which of two situations it is (a row reads 0; no fresh row or unreadable sink) so the next action is unambiguous.
3. The expected first-session store miss does not look like a fault, and every real overlay fault still does.
4. A fresh clone is never set back to a store tip it does not descend from, and the store tip it declines to adopt is never made unreachable.
5. A stale-clone push cannot touch another user's namespace or beat a stale lease generation (pinned against the real hook).
6. A successful replication is observable off-box at a level that ships, without any identifier, and its absence while sessions end is detectable by a read.

**Cut List**

- A scheduled workflow, Sentry cron monitor or Better Stack alert for "zero markers while live" -> property 6 is bought by an owner-run read plus the soak step; a standing alert would be a production-infra surface and a new autonomous task for no additional property today.
- A new sourced lib (`scripts/lib/git-data-pause-scan.sh`) -> CTO F3: about 20 lines of logic; a lib drags in the shard manifest, `test-affected-paths`, durations and `terraform-target-parity` pins.
- A `store_behind` vs `diverged` split of the skip reason -> not implementable on a depth-1 clone (CTO F11); one reason plus an unconditional rescue branch buys property 4 instead.
- Deepening the clone to classify ancestry -> a network call at every session start (CTO F11, rejected).
- A second pause read in the flag-write path -> CTO F10: would put the Better Stack credential beside the flag-write token; the gap is documented instead.
- Changing the `show-ref` masking -> pre-existing, out of Phase A scope (Non-Goals).
- #11704 items 4 (proof-notice routing) and 5 (wrapper comment) -> item 4 may follow; item 5 is a hash-bound edit and is split off by the CTO ruling.

**Applicable institutional learnings**

- `2026-10-31-the-rehearsal-flipped-with-its-own-safety-control-off-and-its-success-signal-never-reached-the-sink.md`: a control is a precondition only if the dispatching step checks it; prove rows of a level reach the sink before trusting a missing success row; grep suites that read the workflow and run them before the first push.
- `2026-10-19-a-precondition-gating-an-irreversible-flip-had-never-run-against-the-live-api.md`: a flip precondition must be run once against the live API before it ships; Phase 1.0 runs the exact SQL read-only against Better Stack.
- `2026-07-15-self-healing-guard-on-a-blind-host-must-fail-safe-on-its-own-instrument.md`: "could not measure" is a probe fault, never a measurement (`pause_unread`, `READ_UNCLEAN`).
- `2026-10-27-a-batch-cap-that-stops-the-night-starves-the-other-tables.md`: Better Stack rows are double-encoded; match on parsed fields, not a bare substring over the quoted row.
- `bug-fixes/2026-06-16-diverged-clone-recovery-branch-aside-before-reset.md`: branch-aside before any destructive move keeps commits reachable (the rescue branch).
- `2026-07-03-base64gzip-hetzner-user-data-and-discrimination-test-must-exercise-sut.md`: a discrimination test must call the function under test (the characterization test runs the real hook through real `git push`).

**Deepen verification record (2026-10-31, live commands against this tree and GitHub)**

- Gates run mechanically: `## User-Brand Impact` present with a valid threshold (4.6); `## Observability` present, all five fields non-placeholder, `discoverability_test.command` starts with `bash`, contains no `ssh`, is a one-script call that finishes inside the 15 s cap when the reader is reachable, `expected_output` is the literal `verdict=`, and `credentials_required` is declared so Check 10 skips it explicitly (4.7); PAT-shape sweep returned no hit (4.8); no UI-surface file in the Files lists (4.9 skipped); no `.tf`, migration, cloud-init or compose file and no new store or connection (4.10 skipped); `python3 scripts/lint-guard-contract.py` green with 4 entries (4.11); `## Scope Check` has the three required subsections with every ask mapped (4.12); no new workflow, Inngest function, check, pg_cron, timer or daemon, so the Task-Design halt does not trigger (4.13).
- Cited issues re-read live: #11704, #8211, #9066, #11433, #10296, #10928, #10901, #10905, #11716, #11717 are all OPEN and say what the plan attributes to them.
- Cited paths verified to exist: `scripts/regenerate-shard-manifest.py`, `scripts/lint-orphan-test-suites.sh`, `tests/scripts/test-argv-bearer-sweep.sh`, `scripts/check-cloudflare-token-drift.test.sh`, `apps/web-platform/infra/web-hosts-fanout-parity.test.sh`, `scripts/regenerate-c4-model.sh`, `plugins/soleur/test/lib/git-fixture-env.ts`, `apps/web-platform/test/helpers/ssh-host-key-fixture.ts`, `plugins/soleur/test/c4-count-parity.test.sh`, the two cited learnings.
- Verify-the-negative: "no origin-push path sends an arbitrary local branch to GitHub" was grepped over `apps/web-platform/server`: the pushes are `session-sync.ts` `HEAD:refs/heads/<KB_SYNC_SIDE_BRANCH>`, `push-branch.ts` `<sha|HEAD>:refs/heads/<branch>` for a named branch, `_cron-safe-commit.ts` `origin <branch>`, and a bare `["push"]` in `session-sync.ts` (pushes the checked-out branch only, which the rescue branch never is). Residual, accepted: a user or agent running `git push --all` from inside their own workspace would push the rescue branch to their own GitHub repository; it contains only that user's own commits.
- "A pino warn is a Sentry breadcrumb only" re-read in `apps/web-platform/server/logger.ts` (`mirrorToSentry`: breadcrumb at warn, `captureException` only for error with an `Error`).
- Post-edit self-audit: the plan no longer references the retired `store_behind`/`diverged` split, `PS10`..`PS12`, `CH4`/`CH5`, `S3` as a reverse-ancestry scenario or a third test file; the remaining mentions of `store_behind` are in the Cut List, the CPO-condition note and the runbook wording that says the warn cannot tell the two apart.
- Test-compatibility audit (tunable semantic change): the workflow step gains lines but no existing semantic changes; suites that read the workflow were enumerated in Phase 5 (`git grep -l 'git-data-cutover'`), including `terraform-target-parity.test.ts` (slices by markers that stay untouched), `git-data-flag-precheck.test.sh` (pins `GIT_DATA_DENY_FLOOR` and `sandbox_deny_floor` only), `web-hosts-fanout-parity.test.sh` and `check-cloudflare-token-drift.test.sh` (count pins that the new step does not move, to be confirmed in Phase 5).

**Related**: #11704, #8211, #9066, #11433, #10296, #10928, #10901/#10905, and the deferrals filed by this plan: #11716 (own-namespace stale-clone overwrite), #11717 (SSH-free hand-back of rescue branches).

## User-Brand Impact

- **If this lands broken, the user experiences:** (1) a real user's fresh session started with the store flag on during the flip window, whose unreplicated worktree is lost at the rollback redeploy; (2) a fresh workspace silently set back to an older store commit (their repository shows old files after the overlay reset), or their replicated-only commits made unreachable after a skipped overlay and the next push; (3) a falsely refused flip that stalls the go-live.
- **If this leaks, the user's workflow data is exposed via:** the new log lines. The info line for the first-session miss and the warn markers carry no user id, workspace id, repository name, path or commit id (integers and bits only); the stderr that contains the bare-repo path (which names the workspace id) is matched but never logged. The only identifier-bearing artifact is the local rescue branch name (12 hex of a commit id), which lives in the user's own workspace and own store namespace and never reaches a log line.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one user's lost or set-back workspace is a trust-ending event for a product whose promise is that the code is safe, so the aggregate tier is too low; CPO concurred (2026-10-31).

CPO sign-off (plan time, 2026-10-31): `yes-with-conditions`. Conditions and where they land: fail closed in A on missing, stale, one-host-only rows and an unreachable sink (Phase 1, `pause_unread`); test the diverged case in B with nothing destructive run and the store tip untouched (Phase 2 real-git rows, plus the rescue branch); track the own-namespace residual (#11716) and name it in the flip runbook (Phase 4); keep C's marker identifier-free (Phase 3 test); skip reasons split into benign and watch-this (superseded by CTO F11: not implementable on a shallow clone, one reason plus rescue); soak read required before the owner is told the soak passed (Phase 4: only `MARKERS_PRESENT` counts). `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Open Code-Review Overlap

None. Seven planned source and test paths were queried against open `code-review` issues; no body names any of them.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "[brief] Flip preconditions (git-data-cutover.yml / its script) must read the per-host reporter line from Better Stack on BOTH hosts and refuse unless `new_sessions_paused=1` in rows under 2 minutes old: `::error ... verdict=pause_not_on` with a `remedy:` line, refusing before any host is touched." | Phase 1 (1.0 to 1.2), Guard 1 | mapped |
| 2 | "[brief] Classify the expected first-session overlay miss (ensure-workspace-repo fetch of a never-provisioned store repository: stderr `does not exist (provision it first)`, exit 128) as info instead of the level-50 `silent fallback` / op git-data-overlay row, keeping real overlay faults at level 50" | Phase 2 (2.1, 2.3, 2.4), Guard 2 | mapped |
| 3 | "[brief] make the session-start overlay `reset --hard` run only when the store tip descends from the clone tip (ancestry check against the fresh clone's tip)" | Phase 2 (2.1, 2.2, 2.4), Guard 3 | mapped |
| 4 | "[brief] add a characterization test that a stale-clone push stays confined to the user's own namespace and the lease fence rejects it (if the test shows cross-namespace overwrite, stop and report instead of papering over it)" | Phase 2 (2.5) | mapped |
| 5 | "[brief] A warn-level, counts-only replication-success marker (no workspace id, repo name or sha) emitted on a successful git-data replication push so it reaches Better Stack" | Phase 3 (3.1, 3.2) | mapped |
| 6 | "[brief] plus a Better Stack read or alert definition for \"zero markers while sessions are live\"" | Phase 3 (3.3), Guard 4 | mapped |
| 7 | "[brief] update the runbook's \"R3 first-session reading\" paragraph to point at the new signal" | Phase 4 (4.1) | mapped |
| 8 | "[brief] Each change gets failing-then-passing tests (the test must go red when the change is removed)" | every Phase's RED step, AC2, AC4 to AC8, the mutation matrices | mapped |
| 9 | "[brief] touch NO hash-bound file ... and do NOT touch the wrapper comment" | Phase 0.2, Phase 5 intersection check, AC10 | mapped |
| 10 | "[brief] Do NOT arm auto-merge or merge ... stop at a ready PR with all checks green and report it" | Phase 6, AC11 | mapped |
| 11 | "[brief] After the PR is ready, tick the matching items in the #8211 plan comment (edit it via gh api, body unchanged otherwise) and add the PR number." | Phase 6 | mapped |
| 12 | "[brief] Do not run scripts/test-all.sh unscoped; run only the scoped suites." | Phase 5 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `.github/workflows/git-data-cutover.yml` pause block; `git-data-cutover-access.test.sh` rows and floors | asks 1 and 8 | asked |
| `ensure-workspace-repo.ts` classifier and ancestry gate; `ensure-workspace-repo.test.ts`; the real-git ancestry test file | asks 2, 3 and 8 | asked |
| `git-data-stale-clone-push.test.sh` | ask 4 | asked |
| `git-data-replication.ts` marker; `git-data-replication.test.ts` | ask 5 | asked |
| `scripts/followthroughs/git-data-replication-signal.sh` and its test | ask 6 | asked |
| runbook edits (R3 paragraph) | ask 7 | asked |
| runbook verdict rows, soak and accepted-gap text | inferred - justification: the suite RB cross-check requires every new verdict word to have a map row, and the CTO round-2 ruling F10 requires the accepted gap to be documented | inferred |
| ADR-068 addendum and the two C4 edge-prose edits | inferred - justification: the plan skill's Architecture Decision gate makes the ADR/C4 update a deliverable of the plan that changes the ordering rule (the rescue branch makes the read gate feed the write's content) | inferred |
| rescue branch `soleur/store-tip-<12 hex>` | inferred - justification: without it the ancestry skip lets the next force-push destroy the only copy of replicated-only commits (architecture review P1, CTO F7/F11); the single-user-incident threshold forbids shipping the skip alone | inferred |
| `scripts/suite-shard-legs.tsv`, `scripts/suite-durations.tsv` (regenerated) | inferred - justification: the repo-global shard-totality ratchet fails CI for a new registered suite otherwise | inferred |
| deferral issues #11716 and #11717 | inferred - justification: workflow rules require a tracking issue for every deferred capability, and the CPO condition asks for the own-namespace residual to be tracked | inferred |
| `tasks.md` | inferred - justification: the work skill executes against it | inferred |

### Split Assessment

- Subsystems touched: 4 - `.github/workflows/`, `apps/web-platform/server|test|infra/`, `scripts/followthroughs/`, `knowledge-base/`
- Planned files: 17 | Estimated changed lines: about 900 (tests dominate; production code about 120 lines)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR - the owner combined A, B and C on 2026-10-31 and the thresholds are met only by test and documentation volume, not by production change surface; a split would also repeat the repo-global ratchet cycle three times

## Files to Edit

- `.github/workflows/git-data-cutover.yml` (step `flip_preconditions`: env `BS_DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN }}` and the pause block last; the final "preconditions clear" echo; the header credential ledger comment, which lists `secrets.DOPPLER_TOKEN` as "bridge + webhook creds")
- `apps/web-platform/infra/git-data-cutover-access.test.sh` (executed rows, mutants, one new `wf.py` row with the verdict-count pin 60 to 61; the `FLOOR=778` assertion floor and `MUTANT_FLOOR=182` restated from a measured run, each with its history comment line)
- `apps/web-platform/server/ensure-workspace-repo.ts` (first-session classifier, ancestry gate, rescue branch)
- `apps/web-platform/server/git-data-replication.ts` (warn success marker, retry flag)
- `apps/web-platform/test/ensure-workspace-repo.test.ts` (mocked rows)
- `apps/web-platform/test/git-data-replication.test.ts` (marker rows, using its existing `vi.doMock` logger pattern)
- `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md` (preconditions list, Verdict map rows, R0/R1 rows, R3 row, "R3 first-session reading", "Known latent behaviours", soak step)
- `knowledge-base/engineering/architecture/decisions/ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md` (dated addendum)
- `knowledge-base/engineering/architecture/diagrams/model.c4` and the generated `model.likec4.json` (prose of the `github -> betterstack` and `hetzner -> betterstack` edges, regenerated with `scripts/regenerate-c4-model.sh`)
- `scripts/suite-shard-legs.tsv` and `scripts/suite-durations.tsv` (via the incremental regenerator, never by hand)
- `scripts/lib/test-affected-paths.sh` only if the affected-suite ratchet names the new files (decide by running it; Phase 5)

## Files to Create

- `apps/web-platform/infra/git-data-stale-clone-push.test.sh` (real git + the real pre-receive hook, read-only)
- `apps/web-platform/test/ensure-workspace-repo-ancestry-real-git.test.ts` (real shallow clones and a shallow store; also holds the real-thrown-shape classifier test with a fake `ssh` on `PATH`)
- `scripts/followthroughs/git-data-replication-signal.sh` and `scripts/followthroughs/git-data-replication-signal.test.sh`
- `knowledge-base/project/specs/feat-one-shot-git-data-flip-preconditions-overlay-success-signal/tasks.md`

Not touched (asserted mechanically in Phase 5): every file in the rung-2 bound set, the transport wrapper and its comment, `git-data-rung2-boot-evidence.env`, any Terraform file, any workflow other than `git-data-cutover.yml`.

## Implementation Phases

Order inside every phase: write the failing test, watch it go red for the right reason, then make the change (`cq-write-failing-tests-before`). Run only scoped suites; never `scripts/test-all.sh` unscoped. All paths below are repository-relative; run from the worktree root.

### Phase 0 — Base and bound-set guard

- 0.1 Confirm the branch is rebased on current `origin/main`; re-read `git ls-files` for the files in Files to Edit (path drift check).
- 0.2 Derive the bound set mechanically (source `tests/scripts/lib/git-data-birth-readiness-gate.sh`, call `git_data_rung2_bound_files`) and keep the command for the Phase 5 intersection check.

### Phase 1 — A: pause precondition (CTO F1, F2, F3, F8, F9, F10)

1.0 **Live dry run first.** Run the exact SQL of 1.2 once, read-only, through `doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh "<sql>"` (a Better Stack SELECT; no write, no dispatch) and record in the PR the shape of the answer (row counts per leg, integer columns, no row bodies). The SQL cannot be validated offline and the 2026-10-19 learning is exactly a precondition that had never run against the live API. Record the observed age of the newest row per host and confirm the 75 s bound is satisfiable by the live cadence.

1.1 **RED first.** In `git-data-cutover-access.test.sh` add an executed-step section `PS` modelled on the `FP` section: slice = the step body from its start through the one-line `fail()` definition, plus the block from the marker comment `# new_sessions_paused (#11704)` to the line before the final `echo "preconditions clear`, plus an end marker. Shims on `PATH`: `doppler` (supports `run ... -- <cmd>` by exec'ing the remainder and logging that `DOPPLER_TOKEN` was set from `BS_DOPPLER_TOKEN`), `sleep` (no-op, logged), and a fake `scripts/betterstack-query.sh` in the fixture workspace that records the SQL argument and answers from a canned `JSONEachRow` file of integers (`{"leg":"web-1","age_s":<n>,"p":<0|1>}`) with a settable exit code. Rows:

| Row | Setup | Expected |
|---|---|---|
| PS1 | both legs: fresh rows, every `p=1`, newest age 40 | slice reaches the end marker; the read happened once; the SQL names `'soleur-web-platform','soleur-inngest-prd'` and `'soleur-web-2'`, `INTERVAL 2 MINUTE`, and the full closed-grammar `match` |
| PS2 | web-1 rows `1,1,0` with the `0` row OLDER than the newest `1` row, web-2 all `1` | exit 1, `verdict=pause_not_on`, a `remedy:` line, end marker not reached, no retry reads logged |
| PS3 | same `0` row on web-2 only | `verdict=pause_not_on` |
| PS4 | web-1 newest row aged 90 s (all `1`) | `verdict=pause_unread` (the F8 bound) |
| PS5 | no rows for web-2 (web-1 green) after three reads | `verdict=pause_unread`; three reads and two sleeps logged |
| PS6 | reader exits non-zero on every attempt (rc 1, 22, 124) | `verdict=pause_unread`; the class token from `bs_read_classify` appears, no credential text |
| PS7 | reader fails on attempt 1, valid on attempt 2 | passes |
| PS8 | a non-integer or missing `p` or `age_s` | `verdict=pause_unread` |
| PS9 | static pins sliced from the marker comment: the block sits after the `sandbox_deny_floor` check and before the final echo; the step env carries `BS_DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN }}` and no step-level `DOPPLER_TOKEN`; no `-x`; the reader substitution is guarded `|| rc=$?`; no `2>/dev/null` inside the new block; the block prints integers and host labels only | `wf.py` +1 row (count pin 60 to 61) plus bash greps scoped to the block |

Mutants (`mutate()` against the extracted step file, then the named PS row goes RED via `mutant_red`): M-ps-removed (delete the block) -> PS2; M-ps-zero-ignored (drop the `pause_not_on` refusal) -> PS2/PS3; M-ps-empty-passes (zero qualifying rows no longer refuses) -> PS5; M-ps-fresh-bound (75 widened to 600) -> PS4; M-ps-grammar-loosened (SQL `match` replaced by a bare substring) -> the PS1 SQL pin; M-ps-token-step-level (token moved back to step-level `DOPPLER_TOKEN`) -> PS9. Restate `FLOOR` and `MUTANT_FLOOR` from a measured run.

1.2 **Implement.** In the step, after the `GIT_DATA_DENY_FLOOR` check and before the final echo, add the marker comment and the block. One read (both hosts in one query), up to three attempts 20 s apart while a leg has no qualifying row: `SELECT multiIf(JSONExtractString(raw,'host_name') IN ('soleur-web-platform','soleur-inngest-prd'),'web-1', JSONExtractString(raw,'host_name') = 'soleur-web-2','web-2','') AS leg, dateDiff('second', dt, now()) AS age_s, toUInt8OrNull(extract(raw,'new_sessions_paused=([01])')) AS p FROM remote($BS_TABLE) WHERE dt > now() - INTERVAL 2 MINUTE AND leg != '' AND match(raw,'agent_sessions_live=[0-9]+ cc_queries=[0-9]+ legacy_sessions=[0-9]+ starting=[0-9]+ new_sessions_paused=[01] refused_since_last=[0-9]+') ORDER BY dt DESC LIMIT 200 FORMAT JSONEachRow`. The reader runs as `env DOPPLER_TOKEN="$BS_DOPPLER_TOKEN" doppler run --preserve-env -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh "<sql>"` with `|| rc=$?` so `set -e` cannot end the step without a verdict, and its stderr surfaced through the existing classifier pattern (never discarded). Per leg: any `p=0` -> `fail pause_not_on` (checked across both legs before any unread verdict); zero rows, newest `age_s` above 75, a read failure or any non-integer -> `fail pause_unread`. Annotation text carries integers and the host label only (`web-1 rows=N zeros=Z newest_age_s=A`). Remedies: `pause_not_on`: "turn the pause on (flip.sh new-sessions-paused prd on, owner terminal), wait 2 minutes so no `=0` row remains in the window, then re-dispatch; note that `new_sessions_paused=1` does not mean zero sessions (the exempt synthetic account can still start one), so read `agent_sessions_live` too"; `pause_unread`: "no reporter row under 75 s old for <label>, or the Better Stack read failed: check the heartbeat and the reader credentials, then re-dispatch". Update the final echo to name the pause, and the header credential ledger comment (`secrets.DOPPLER_TOKEN` now also feeds the precondition step's Better Stack read). The existing `# deploy_in_flight` marker (sliced by `terraform-target-parity.test.ts`) and `# d6_replace_stale (#10166)` marker (sliced by the FP rows) stay untouched, and `fail()` stays one line (it is extracted by regex).

### Phase 2 — B: overlay (CTO F4, F5, F7, F11)

2.1 **RED first (mocked)** in `ensure-workspace-repo.test.ts` (hoist a `mockLogWarn`; the logger mock currently gives `warn: vi.fn()`). Fewer fixtures: variants of the classifier live in 2.3, so here:

- first-session miss (rejection `Error` with `code: 128` and the real-shaped stderr "remote: git-data transport: repo does not exist (provision it first): '/srv/x/ws-uuid.git'\nfatal: Could not read from remote repository.") -> outcome `ok`, `mockReportSilentFallback` NOT called with op `git-data-overlay`, `mockLogInfo` called with an action token, no reset, and `JSON.stringify` of every log call contains neither `u1`, `ws-uuid` nor the path.
- a non-miss fetch failure ("git-data unreachable") stays level 50 (existing row (e) retained).
- descends: `merge-base --is-ancestor HEAD <dataRef>` resolves -> `reset --hard` runs, call order merge-base then reset.
- not descendant (`merge-base` rejects with `code: 1`) -> `git branch soleur/store-tip-<12 hex of rev-parse <dataRef>>` is called BEFORE anything else, no reset, `mockLogWarn` with op `git-data-overlay-not-descendant` (no ids), no `reportSilentFallback`, outcome `ok`.
- not descendant and branch creation fails (non-idempotent failure) -> `reportSilentFallback` op `git-data-overlay`, NO reset, outcome `ok`; branch already exists at the same sha -> treated as success.
- `merge-base` rejects with `code: 128` -> level-50 catch, no reset, no branch.

2.2 **RED first (real git)** `ensure-workspace-repo-ancestry-real-git.test.ts`: no `fs` mock. Build an origin repo, a bare store with `receive.shallowUpdate=true`, a user clone (`--depth 1`) with one local commit pushed to the store, then drive the real `ensureWorkspaceRepoCloned` with the injected graft doing a real `git clone --depth 1` and `fetchFromGitData` replaced by a real `git fetch --update-shallow <store> +refs/heads/*:refs/remotes/git-data/*`. Scenarios: S1 origin unmoved (store tip descends from the shallow clone tip, both shallow) -> HEAD equals the store tip; S2 origin advanced (not descendant) -> HEAD and working tree unchanged, the store ref byte-identical, the rescue branch exists at the store tip; S3 origin advanced by exactly the store tip's ancestor on a shallow clone (the "store behind" shape that depth 1 cannot prove) -> same outcome as S2, pinning that the benign case is also rescued; S4 the follow-up: a real `git push --force` of `refs/heads/*` from the S2 workspace into the store namespace leaves the old store tip reachable (as `heads/soleur/store-tip-<12 hex>`). Git env via `gitFixtureEnv(dir)` from `plugins/soleur/test/lib/git-fixture-env` for fixture setup; the system under test's own `realLocalGit` inherits `process.env`, and the vitest `globalSetup` tripwire already aborts a runner that holds a `GIT_*` location variable, so no extra scrub is needed (state this in the file header).

2.3 **RED first (real thrown shape; same file)** (CTO F5 condition): put a fake `ssh` that prints the wrapper's refusal and exits 1 first on `PATH`, call the real `gitWithPrivateKeyAuth(["fetch", ...])` with the pin fixture from `test/helpers/ssh-host-key-fixture`, capture the thrown error, and assert the exported classifier returns true for it and false for variants (same text with `code` 1, `code` undefined, a 128 with "Permission denied (publickey)"; true for 128 with the phrase only in `message`); a marker file proves the fake `ssh` was the one used. A row greps the bound wrapper source (read-only) for the exact phrase so a wrapper wording change fails here instead of silently never matching.

2.4 **Implement** in `ensure-workspace-repo.ts`: export `isFirstSessionStoreMiss(err)` (numeric `code === 128` AND `/does not exist \(provision it first\)/` over `err.stderr` falling back to `err.message`); in the overlay `catch` call it first and `log.info({ action: "git-data-overlay-first-session-miss" }, "<fixed string>")`, otherwise the unchanged `reportSilentFallback`. In the reset block, inside the existing workspace lock and after the validity re-check, run `localGitFn(["merge-base","--is-ancestor","HEAD",dataRef])`: resolve -> reset; reject with `code === 1` -> `rev-parse <dataRef>`, `git branch soleur/store-tip-<12 hex> <dataRef>` (no `-f`; "already exists at the same sha" is success; any other failure rethrows into the level-50 catch before anything is skipped), then `log.warn({ op: "git-data-overlay-not-descendant" }, "<fixed string>")`; any other rejection rethrows into the level-50 catch.

2.5 **Characterization** `apps/web-platform/infra/git-data-stale-clone-push.test.sh` (auto-registered by presence): build a bare repo, install the real `git-data-pre-receive.sh` as `hooks/pre-receive` (read-only copy), set `receive.advertisePushOptions=true` and `receive.shallowUpdate=true`, and push for real with `git push --force --push-option=lease-gen=N --push-option=worktree-id=W` using a constructed git environment. Rows: CH1 a stale clone pushing `refs/heads/*` into a peer's `refs/soleur/worktrees/P/` is rejected with the hook's namespace text and the peer's refs are byte-identical afterwards; CH2 a push at a lease-gen lower than the stored max is rejected with the hook's `stale lease generation` text and the ref is unchanged; CH3 a stale clone at the CURRENT generation overwrites its OWN namespace tip (accepted; labelled the accepted residual tracked in #11716, so a future fix flips it deliberately). The hook's rejection strings are asserted. **Stop rule:** if any row shows a write outside the pusher's own namespace, halt the work phase and report instead of adjusting the assertion.

### Phase 3 — C: success marker and read (CTO F6)

3.1 **RED first** in `git-data-replication.test.ts` (existing `vi.doMock("../server/logger")` pattern, installed before the dynamic import because `log` is created at module init): successful push -> exactly one warn call with message `git_data_replication_success=1 transient_retried=0` and fields exactly `{gitDataReplicationSuccess: 1, transientRetried: 0}`; the serialized call contains no `workspaceIdHash`, `worktreeIdHash`, hex run of 8 or more, UUID or `leaseGeneration`; retry path -> `transient_retried=1`; failure, shed and pin-fault paths -> no marker; a row greps `apps/web-platform/server` for a second occurrence of the marker phrase (the read counts it by substring). Deleting the `log.warn` turns these red.

3.2 **Implement** in `git-data-replication.ts`: a `retried` flag set in the transient-retry branch; after the existing info line (left untouched) one `log.warn({ gitDataReplicationSuccess: 1, transientRetried: retried ? 1 : 0 }, "git_data_replication_success=1 transient_retried=" + (retried ? 1 : 0))`.

3.3 **Live dry run, then RED first, then implement** `scripts/followthroughs/git-data-replication-signal.sh` and its test. Before writing it, run its SQL once read-only against Better Stack (it will return zero markers before the release; the point is that the query parses and the reporter aggregate returns integers per host). The test copies the script into a temp tree beside a fake `scripts/betterstack-query.sh` (the script derives its root from its own location; ADR-214, no test seam in the script). Usage `--since <window>` (validated charset), read-only, aggregated in SQL (integers only, never row bodies, never host names), hot window UNION archive (`$BS_TABLE` / `$BS_TABLE_S3`). Per host (web-1, web-2): marker count (`match(raw, 'git_data_replication_success=1 transient_retried=[01]')`), reporter-row count, rows with `agent_sessions_live>0`, the newest reporter row's live value and age, the age of the last live row. One line per host and one overall line `verdict=<TOKEN> ...`; the overall verdict is the worst of the two. Tokens and exit codes: `MARKERS_PRESENT` 0 (every host that had a live row has a marker; the only positive evidence); `NO_SESSIONS` 4 (inconclusive, never a pass: reporter rows present, no live session, no marker); `PENDING` 3 (a live row, zero markers, but the newest row still reads live or the last live row is under 10 minutes old); `ZERO_MARKERS_WITH_SESSIONS` 1 (investigate: a live row, newest row 0, last live row at least 10 minutes old, zero markers on that host); `READ_UNCLEAN` 2 (any read failed or either host has no reporter row; outranks everything). Refuses under `-x` with a live credential (exit 78). Test rows: one per verdict, per-host masking (markers on web-2 do not rescue a silent web-1), precedence (`READ_UNCLEAN` beats `MARKERS_PRESENT`), a host with no reporter row, reader failure classes, SQL shape pins, output carries no host name.

### Phase 4 — Docs and records

- 4.1 Runbook: list `pause_not_on` and `pause_unread` among the `Flip preconditions` refusals; add two Verdict-map rows (suite RB checks that every map word has an emitter outside `*.md`/tests, which the workflow satisfies); state that the pause is a precondition-time check, not a lock held across the sequence, and that `new_sessions_paused=1` does not mean zero sessions (exempt account); R0/R1 rows: "enforced by the workflow now, read it anyway"; R3 row and the paragraph "R3 first-session reading": keep the Rehearsal 2 history, add that on an image carrying this change the first-session overlay row is info (so it no longer appears at level 50), that positive evidence of replication in the window is `scripts/followthroughs/git-data-replication-signal.sh --since '<window start>'` reading `MARKERS_PRESENT` (the marker exists only on images from the release carrying this change: read `/health` first; the read is meaningful only while the store flag is on and for sessions that connected a repository), and that `refs_assert` after the rollback stays the store-side proof; soak step 8: only `MARKERS_PRESENT` satisfies the signal read before the owner is told the soak passed; "Known latent behaviours": the ancestry gate and the rescue branch now exist, the stale-clone own-namespace overwrite is characterized and accepted with #11716, the rescue branches' hand-back is #11717, and `git-data-overlay-not-descendant` is expected after any GitHub-side change (watch its count, not a single row; it cannot tell "store behind" from "diverged").
- 4.2 ADR-068 addendum dated 2026-10-31 (#11704): the overlay reset is ancestry-gated (read side); writes remain fence-ordered; the rescue branch means the read gate now feeds the write's content, so the two are no longer independent; why one reason; the accepted residual and its tracking issues.
- 4.3 C4: add the flip-time pause read and the replication-success marker to the `github -> betterstack` and `hetzner -> betterstack` edge prose in `model.c4`; regenerate `model.likec4.json` with `scripts/regenerate-c4-model.sh`; run `plugins/soleur/test/c4-count-parity.test.sh` and `apps/web-platform/test/c4-code-syntax.test.ts`.
- 4.4 Specs: `tasks.md` derived from these phases (after plan review).

### Phase 5 — Repo-global ratchets and scoped runs (before the first push)

Run, scoped: `bash apps/web-platform/infra/git-data-cutover-access.test.sh`, `bash apps/web-platform/infra/git-data-flag-precheck.test.sh`, `bash apps/web-platform/infra/git-data-stale-clone-push.test.sh`, `bash apps/web-platform/infra/git-data-pre-receive.test.sh`, `bash apps/web-platform/infra/web-hosts-fanout-parity.test.sh`, `bash scripts/check-cloudflare-token-drift.test.sh`, `bash tests/scripts/test-argv-bearer-sweep.sh`, `bash scripts/followthroughs/git-data-replication-signal.test.sh`, `bun test plugins/soleur/test/terraform-target-parity.test.ts` (the `flip_preconditions` slice pins), `bash plugins/soleur/test/c4-count-parity.test.sh`, the vitest files named above, `python3 scripts/regenerate-shard-manifest.py --incremental --write`, `bash scripts/lint-orphan-test-suites.sh`, `python3 scripts/lint-guard-contract.py`, `python3 scripts/lint-infra-no-human-steps.py` over the plan, and `git grep -l 'git-data-cutover' -- '*.test.sh' '*.test.ts'` then run every hit (line-count pins). Mechanical constraint checks: the intersection of `git diff --name-only origin/main...HEAD` with the Phase 0 bound set is empty; the diff does not contain `git-data-transport-wrapper.sh`; secret-scan before every push; no `git stash`.

### Phase 6 — Ship (no merge)

PR #11713 body ends with `Ref #11704`, `Ref #8211` and the Generated-with line; commit trailers carry `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`; mark ready with all checks green; do not arm auto-merge. Then edit the #8211 plan comment through the API: tick the matching Phase A items and add the PR number, body otherwise unchanged. Report the PR as ready and owner-gated.

## Acceptance Criteria

### Pre-merge (PR)

- AC1 `git-data-cutover-access.test.sh` rows PS1..PS9 pass, every M-ps-* mutant goes RED for its named row, the verdict-count pin reads 61, and `FLOOR` / `MUTANT_FLOOR` are restated from a measured run.
- AC2 With the pause block deleted from the workflow, PS2 fails (the test goes red when the change is removed).
- AC3 The refusal strings are `::error title=git-data-cutover preconditions::verdict=pause_not_on` and `...verdict=pause_unread`, each followed by a `remedy:` line, both before the bridge step; the PR records the live read-only dry run of the exact SQL (shape only).
- AC4 `ensure-workspace-repo.test.ts` mocked rows and the real-git rows S1..S4 pass; with the classifier removed the first-session row fails; with the ancestry gate removed S2 fails; with the rescue-branch creation removed S2 and S4 fail.
- AC5 The real-thrown-shape rows pass against the real error and a classifier that reads only `message` with no numeric-code check fails them.
- AC6 `git-data-stale-clone-push.test.sh` CH1..CH3 pass against the unmodified bound hook; no row shows a write outside the pusher's namespace.
- AC7 `git-data-replication.test.ts` marker rows pass; with the `log.warn` deleted they fail; the serialized marker contains no identifier or hash-shaped token.
- AC8 `git-data-replication-signal.test.sh` passes every verdict row, the per-host masking row and the precedence row; output contains no host name; only `MARKERS_PRESENT` exits 0.
- AC9 The runbook edits of Phase 4.1 exist (`grep -c 'pause_unread'` on the runbook is at least 2; the R3 paragraph names `git-data-replication-signal.sh`); the ADR-068 addendum and the two C4 edge edits exist and the C4 tests are green.
- AC10 No file in the bound set, no Terraform file, no other workflow, and not `git-data-transport-wrapper.sh` appears in the diff.
- AC11 All Phase 5 scoped suites and ratchets are green; PR checks are green; the PR is ready and NOT merged, and auto-merge is NOT armed.
- AC12 `Ref #11704` and `Ref #8211` only (no closing keyword) in the PR body; #11716 and #11717 are referenced as the tracked residuals.

### Post-merge (owner-gated, not performed by this task)

- The merge and its release are owner decisions (production behaviour changes). The first release carrying the marker is the floor for reading R3 positive evidence. The #8211 comment is ticked at PR-ready time, not at merge.

## Test Scenarios

The executed rows PS1..PS9, the mocked and real-git overlay rows, CH1..CH3 and the signal verdict rows above are the scenarios; each red-then-green pair is listed with the change it guards. Adversarial shapes included on purpose: a stale newest row, a `0` row that is not the newest, a non-integer age, a reader that fails then recovers, a 128 with a different stderr, a phrase with the wrong exit code, a shallow store tip, an origin that advanced past the store.

## Guard Contract

### Guard 1 — flip pause precondition

**Property.** No `mode=flip` run proceeds past `Flip preconditions` unless both web hosts have at least one reporter row in the last 2 minutes, the newest at most 75 s old, and every such row reads `new_sessions_paused=1`.

**Assembly.** Every path by which the step could pass without that fact: the two legs (web-1 with its two possible host names, web-2) in one query, the retry loop, the SQL-side closed-grammar match and integer extraction, the zero, empty, stale, non-integer and read-failure arms, and the step's position before the SSH bridge. The chokepoint is the step's `fail()`; the block is reached on every flip dispatch because the step is gated only on `mode == 'flip'`.

**Mutation matrix.**

| Edit that MUST turn a named case RED | Case |
|---|---|
| delete the whole block (own dispatch: the slice reaches the end marker with no read performed) | PS2 and the read-count assertion of PS1 |
| second member after a compliant first: judge only the first leg | PS3 |
| `=0` refusal neutered | PS2, PS3 |
| freshness bound widened | PS4 |
| empty qualifying set passes | PS5 |
| bare substring instead of the closed grammar | the PS1 SQL pin |
| token moved to step level | PS9 |

**Harness rows.** PS1's must-PASS fixture differs from the canonical in leg order and extra non-qualifying rows; a self-check asserts the shim reader was actually invoked (a slice that never reads must not pass PS1). **Anchor.** The refusal words must stay in sync with the runbook Verdict map; suite row RB cross-checks every map word against an emitter outside `*.md` and the tests.

### Guard 2 — first-session classification

**Property.** An overlay error is downgraded to info only when it is a git exit 128 whose stderr names the unprovisioned repository; every other overlay error stays level 50.

**Assembly.** The classifier function, its single call site in the overlay `catch`, the three inputs it reads (`code`, `stderr`, `message`), and the real thrown shape produced by `gitWithPrivateKeyAuth`.

**Mutation matrix.**

| Edit that MUST turn a named case RED | Case |
|---|---|
| remove the code check (phrase alone downgrades) | the `code` 1 row |
| remove the phrase check (any 128 downgrades) | the Permission-denied 128 row |
| classifier never called (own dispatch) | the first-session row |
| second member: downgrade also on a second phrase | the `code` undefined row |
| read only `message` | the real-shape row with stderr only |

**Harness rows.** The real-shape rows fail if the fake `ssh` is not used (marker file); a must-PASS differs from the canonical by carrying the phrase in `message` only. **Anchor.** The phrase is owned by the bound wrapper; a row greps the wrapper source (read-only) for it.

### Guard 3 — ancestry-gated overlay reset

**Property.** `reset --hard` onto the store tip runs only when the store tip descends from the fresh clone tip, and a store tip that is not adopted is first preserved on a local branch.

**Assembly.** The single `reset` call site in the overlay, executed under the workspace lock; the `merge-base` result handling (0, 1, other); the rescue-branch creation and its failure arm; the next replication push that carries the branch.

**Mutation matrix.**

| Edit that MUST turn a named case RED | Case |
|---|---|
| remove the ancestry call | S2 and the not-descendant mocked row |
| treat exit 1 as descends | S2 |
| treat any rejection as skip (exit 128 swallowed) | the code-128 row |
| skip without creating the rescue branch | S2, S4, the mocked branch-order row |
| rescue-branch failure skips anyway instead of failing into the catch | the branch-failure row |
| swap the argument order (`dataRef HEAD`) | S1 |

**Harness rows.** S1 is a must-PASS that is not the canonical (shallow store and shallow clone), with a self-check that HEAD actually moved. **Anchor.** The ancestry fact comes from the repository, not a stored value.

### Guard 4 — zero-markers read

**Property.** The read never reports a pass-like verdict when it could not read a reporter row on both hosts, a silent host is never masked by a healthy one, and only `MARKERS_PRESENT` is positive evidence.

**Assembly.** Both hosts' reporter reads, the marker read, the per-host verdicts, the worst-of aggregation, the precedence order, the 10-minute settle rule and the exit codes.

**Mutation matrix.**

| Edit that MUST turn a named case RED | Case |
|---|---|
| precedence swapped (`MARKERS_PRESENT` before `READ_UNCLEAN`) | the precedence row |
| drop the settle rule | the `PENDING` row |
| second member: the aggregation looks at the first host only | the per-host masking row |
| read failure counted as zero rows | the reader-failure rows |
| `NO_SESSIONS` exits 0 | the exit-code row |

**Harness rows.** The fake reader's invocation count is asserted (a script that never reads cannot pass); a must-PASS differs from the canonical in host order. **Anchor.** none beyond the test: the verdict depends on live reads.

## Observability

```yaml
liveness_signal:
  what: the per-host reporter line agent_sessions_live=... new_sessions_paused=... (one row per host per minute) and the new git_data_replication_success=1 warn marker (one row per successful replication push)
  cadence: reporter 60s per host; marker per session end
  alert_target: none new - the existing git-data heartbeats and pin-fault rule stay the pages; the marker is read by the owner-run signal script during R3 and the 7-day soak
  configured_in: apps/web-platform/server/quiet-window.ts and apps/web-platform/server/git-data-replication.ts (log.warn) reaching Better Stack via the container stdout shipper at WARN and above
error_reporting:
  destination: Better Stack Logs (warn rows) and the workflow run log (verdict annotations); Sentry unchanged (real overlay faults still reportSilentFallback at level 50; the not-descendant skip is a pino warn breadcrumb only)
  fail_loud: workflow annotation ::error title=git-data-cutover preconditions::verdict=pause_not_on or verdict=pause_unread; signal script exit code 1, 2 or 4
failure_modes:
  - mode: pause off or a host unread at flip dispatch
    detection: the Flip preconditions step itself (fresh rows, fail closed)
    alert_route: the dispatching run fails red before any host is touched
  - mode: success marker never reaches the sink or the image lacks it
    detection: git-data-replication-signal.sh verdict ZERO_MARKERS_WITH_SESSIONS, READ_UNCLEAN or NO_SESSIONS
    alert_route: owner-run read in R3 and the soak step; no standing alert (see Cut List)
  - mode: overlay skipped because the store tip is not a descendant of the GitHub clone
    detection: Better Stack row git-data-overlay-not-descendant (warn ships); the count is what to watch
    alert_route: runbook Known latent behaviours; hand-back of rescue branches tracked in #11717
  - mode: real overlay fault or rescue-branch creation failure
    detection: unchanged level-50 ensure-workspace-repo silent fallback op git-data-overlay in Sentry and Better Stack
    alert_route: existing Sentry rules
logs:
  where: Better Stack Logs source 2457081 (host_name soleur-web-platform or soleur-inngest-prd for web-1, soleur-web-2 for web-2), hot window then archive
  retention: the Better Stack plan retention; the hot window is about 40 minutes, so reads that span longer use the archive arm (the signal script does)
discoverability_test:
  command: bash scripts/followthroughs/git-data-replication-signal.sh --since 15m
  expected_output: verdict=
  credentials_required: BETTERSTACK_QUERY_HOST, BETTERSTACK_QUERY_USERNAME and BETTERSTACK_QUERY_PASSWORD from Doppler soleur/prd_terraform - Better Stack log rows have no unauthenticated reader, so no probe verifies the same property without them
```

Affected-surface note (blind execution surfaces): the overlay runs inside the web container, which is not directly inspectable; the structured fields of the overlay lines (`action` / `op`) discriminate first-session miss, not-descendant skip and real fault in one event each, and the real-fault path keeps its existing level-50 event.

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO, sign-off only)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Ruled by CTO agent, 2026-10-31 on F1..F11 (recorded in `knowledge-base/project/specs/feat-one-shot-git-data-flip-preconditions-overlay-success-signal/decision-challenges.md`). Plan review (DHH, Kieran, code-simplicity, architecture, spec-flow) adopted: the rescue branch (architecture P1), one skip reason (Kieran P1, DHH, simplicity), SQL-side integers and per-command token (architecture P2), the 75 s freshness bound, per-host signal verdicts and a non-zero `NO_SESSIONS`, the two assertion floors, scoped PS9 pins, and trimmed PS rows and test files. Not adopted: dropping the retry loop (CTO's ingest-lag risk), dropping `transient_retried` (CTO F6), dropping the third characterization-adjacent rows beyond CH1..CH3 (already trimmed).

### Product (CPO)

**Status:** reviewed (no UI surface; sign-off only)
**Assessment:** `yes-with-conditions`, threshold `single-user incident` concurred; conditions mapped in User-Brand Impact (one superseded by CTO F11 with the reason recorded). No UI file in Files to Edit/Create, so no wireframe and no Product/UX gate.

Skipped domains and why: Legal/CLO (the new log lines carry no personal data; the info line is free of ids by test), Operations (the runbook edits document existing owner procedures), Marketing, Finance, Sales, Support (no surface). GDPR gate: none of the canonical regex surfaces (schemas, migrations, auth, API routes, `.sql`) and none of triggers (a) to (d) are touched; the counts-only rule is enforced by tests.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-068 with a dated addendum (2026-10-31, #11704): the session-start overlay reset is gated on ancestry of the store tip over the fresh clone tip; writes remain ordered by the fence; a skipped adoption first preserves the store tip on a local `soleur/store-tip-<12 hex>` branch that the next replication push carries into the store, so the read gate now feeds the write's content; one skip reason because depth-1 clones cannot prove "store behind"; the own-namespace stale-clone overwrite is a characterized, tracked residual (#11716). This is an in-PR deliverable, not a follow-up.

### C4 views

External humans (founder/owner): unchanged, no new actor. External systems (Better Stack `betterstack`, GitHub `github`, Doppler `doppler`): all modeled; no new system. Containers and stores (`gitDataStore` at `platform.infra.gitDataStore`): unchanged, no new store. Actor-to-surface access relationships: unchanged. The only C4 edit is the prose of two existing edges, `github -> betterstack` (CI polls Logs via `betterstack-query.sh`: add the flip-time pause read) and `hetzner -> betterstack` (the web container's pino stdout at WARN and above: add the replication-success marker), per the ADR-263 precedent; `model.likec4.json` is regenerated; `c4-count-parity` and the C4 syntax test run in Phase 5 as the cardinality check.

### Sequencing

The addendum describes behaviour that is true once this PR is deployed; it is written in this PR.

## Non-Goals

- Changing the write path, the pre-receive hook or any bound payload (the own-namespace overwrite fix is #11716, batched with the next hash-bound PR; the SSH-free hand-back of rescue branches is #11717).
- Fixing the `show-ref` masking (a failed `show-ref` of any kind reads as "ref absent"); it predates this work and the new gates stay safe under it (a masked failure only means no reset).
- #11704 item 4 (proof-notice routing) and item 5 (wrapper comment), per the CTO ruling.
- A standing Better Stack alert, scheduled workflow or Terraform for the zero-marker condition (Cut List).
- Any dispatch of `git-data-cutover.yml` or any `workflow_dispatch`, any `flip.sh` run, any Doppler write, any merge.

## Risks and Sharp Edges

- The 2-minute window means a pause turned on less than 2 minutes before the dispatch can still show an older `=0` row and refuse; the remedy says to wait (CTO F1). The 75 s freshness bound means a lagging ingest can refuse a healthy host; three bounded reads absorb a poll or two, and a persistent absence is exactly `pause_unread`.
- The SQL (multiIf, extract, match, dateDiff on `remote($BS_TABLE)`) cannot be validated offline; Phase 1.0 and 3.3 run it once, read-only, against the live sink before the tests are trusted.
- The step also holds `GH_TOKEN` and the Sentry read token: the Better Stack credential is bound per command (`BS_DOPPLER_TOKEN`), the block never enables `xtrace` and never prints reader stderr verbatim.
- The step body is sliced by two other suites (`# d6_replace_stale (#10166)` and `# deploy_in_flight` markers, plus a one-line `fail()` regex); the new block goes after both and `fail()` stays one line.
- A shallow store makes ancestry answers conservative: an unprovable ancestry reads as not-descendant and skips (safe direction, now that the store tip is preserved); the extra store heads this creates are bounded by the existing gc.
- The pause check is a precondition-time check, not a lock (CTO F10): a host restart between the check and the flag write is covered by the owner's re-reads, the finalizer and the go gate, and documented in the runbook.
- The marker phrase must not appear in any log other than the success branch (the read counts it by substring); a Phase 3 row greps the server tree.
- A plan or task text that pairs a human actor with an infrastructure imperative trips `lint-infra-no-human-steps`; the lint is part of Phase 5.
- The worktree directory was removed by an external cleanup once during planning: commit and push plan artifacts early.
