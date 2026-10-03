---
title: "git-data cutover: close the residual gaps in the real modes (#8211)"
date: 2026-10-02
slug: git-data-cutover-residual-real-mode-gaps
branch: feat-8211-git-data-real-modes
issue: 8211
type: feat
lane: cross-domain
requires_cpo_signoff: true
---

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Overview

Issue #8211 asked for the real cutover, rollback and wipe modes to be rebuilt on real mechanisms. A premise check against `origin/main` (493c859960) shows that work has largely landed: PR #9226 (merged 2026-09-30) shipped the `proof`, `freeze`, `unfreeze`, `probe`, `flip`, `rollback` and `redeploy` modes and the `git-data-host-rotate` apply arm, and ADR-239 removed the runtime repoint, the rsync and the plaintext wipe by serving the store from LUKS at birth. The user chose (2026-10-02) to scope this plan to the **residual gaps** found by auditing each requested property against `main`, plus the adjacent items, and to build nothing that has no remaining attachment point.

**Slicing (from plan review).** Three deliverables, none touching a hash-bound host payload, so none can void the rung-2 evidence that gates the next `git_data_host_replace`:

- **PR-A — cutover hardening** (P1, P2, P3, P4, P7): the one PR that carries the CPO conditions. `Refs #8211`, never `Closes #8211`: the flip and the flag-write credential stay open.
- **PR-B — #9395 apt bounding** (P5): test-infra only, shares no failure mode with the cutover, so it must not delay PR-A.
- **P6 — #9066 closeout**: verification, a comment and at most an ADR/runbook line. It does not wait on PR-A because of the 2026-10-24 CLO deadline.

Running `mode=flip`, `git-data-host-rotate`, defining the flag-write credential and every other production step stay behind the reviewer-gated environment and the user's per-step authorization; they are sequenced at the end, not performed.

## Premise Validation (Phase 0.6)

Checked: every cited issue via `gh`, every cited file via `git ls-files`/`git show origin/main`, the proposed mechanisms against ADR-068/220/239/241.

| Cited / assumed | Reality on main | Plan response |
|---|---|---|
| "real modes were deleted; rebuild them" | Rebuilt by #9226; modes proof/freeze/unfreeze/probe/flip/rollback/redeploy exist (`git-data-cutover.yml` header, `git-data-cutover.sh`) | Re-scope to residual gaps (user-confirmed) |
| wipe mode + store-empty gate | No wipe path; `CONFIRM_WIPE` refused; ADR-239 makes wipe a render branch needing its own rung-2 rehearsal | Moot; Cut List |
| `assert_distinct_endpoints` before rsync | No rsync remains; the G2 census bans it | Moot; belongs to #8571 copy mode |
| `verify_set_identity` | Existed only in the deleted body (`0777caa9e`) | Moot |
| rollback restarts webhook unit first | Rollback is flag-off + `/hooks/deploy` redeploy; no webhook unit is stopped | Moot |
| ADR-220 D2 rollback/notify job split | One `cutover` job with an `if: always()` finalizer; no notify job exists | Built as P2 |
| "key rotation is a reviewed PR adding a typed arm to `apply-git-data-root-key.yml`" | That workflow handles the SSH root key only. LUKS rotation is `apply_target=git-data-host-rotate` in `apply-web-platform-infra.yml`, `confirm=ROTATE-GIT-DATA`, `served_repos=0` precondition | Stale; no PR needed |
| windowed prd flag-write token "none exists" | Consumed as `secrets.DOPPLER_TOKEN_GIT_DATA_FLAG`; fails closed with `flag_write_credential_absent`; defined nowhere in repo; one secret serves flip, rollback and finalizer although #8573 asked for two | Genuine gap, blocked on #8609/#8209; tracked on #8573 with a preflight (P7) |
| #7226, #8210 preconditions | Both CLOSED (pin live; `RUNG2_REBOOT_REOPEN=PASS`) | Not blocking |
| #8209, #8609 preconditions | OPEN (see Authorization-gated sequence) | Block the real flip, not this work |
| Erasure during `flag=true` could re-serve a plaintext copy after rollback (spec-flow) | ADR-239: the plaintext volume is never mounted and rollback is flag-off only; data stays on LUKS | Verified moot at work time by citing ADR-239 decisions 1–2 and the removed tier-2 rollback; recorded in the runbook |

## Research Insights

**Property List** (what the original ask buys, as observable outcomes) and where each stands:

1. After a flip or rollback, flag state is read from inside each running web container, not from Doppler — IMPLEMENTED (`git-data-cutover.yml` step "Per-host git_data_store= assertion", exits 1 with `verdict=deploy_assert_failed`; line emitted at `server/git-data-replication.ts:301`).
2. Every host in `var.web_hosts` is redeployed and read back — PARTIAL: redeploy and finalizer use the parity-pinned `WEB_HOST_PRIVATE_IPS`; the readback loop hardcodes `web-1|…` and `web-2|…` (`git-data-cutover.yml:468`) and no test ties it to `var.web_hosts`.
3. The flag write uses a credential only a reviewer-gated job can use, for a bounded window — GAP (blocked; #8573).
4. A failed, stranded or cancelled cutover cannot leave the freeze sentinel or the flag in a surprising state without someone being told — PARTIAL: the finalizer unwinds, but `FREEZE_HELD` and `RECOVERY_FAILED` are only `::error` lines; no notify job (the header's "emits a paging line" is unverified).
5. The freeze has one defined writer and a pre-run absence check — IMPLEMENTED (`mode_freeze`; the `probe=store-verified` read refuses `cutover_frozen`).
6. Before approving, a reviewer can read how long each mode makes the app unavailable — GAP (only the G3 host replace has a downtime statement, runbook ~line 808).
7. Rollback is shown to leave erasure working (CPO condition on #8211, from PR #9048) — GAP: only `flip` runs the provision → push → remove probe (`git-data-cutover.yml:506-513`).
8. The git-data host is observable after boot — PARTIAL GAP: no Vector on the host; `boot_complete` last seen 2026-09-25; no recurring signal and no tracker.

**Cut List** (mechanism → property → what already covers it):

- `assert_distinct_endpoints`, rsync/repoint, hooks copy → nothing left to protect → ADR-239 has no copy; #8571 owns it.
- wipe mode and the store-empty gate → no wipe path exists → `CONFIRM_WIPE` refused; ADR-239 render branch.
- `verify_set_identity` → deleted function → probe uses a synthetic id (`cutover-probe-<lineage>`).
- webhook-unit-first rollback ordering → rollback no longer stops a unit → flag-off + redeploy.
- `apply-git-data-root-key.yml` typed rotation arm → wrong workflow; `git-data-host-rotate` exists with 56 gate tests.
- `TOFU_ARM` refusal in the precheck → #5914 closed and the unpinned arm deleted by #9096; precheck reads `absent`; a test pins the deletion.
- #8571 copy mode → needed only before the first rotation of a populated store; trigger unmet. Re-evaluation note only.
- #9394 → user decision; surfaced, not decided.
- #8093 items → each is a hash-bound payload change that voids rung-2 evidence; bundle with the next planned template change; no work here.
- Log shipping on the git-data host → a recurring signal needs a host-side timer (hash-bound); tracking issue filed in P7, made a flip precondition.
- ADR-220 amendment for the notify job → PR description plus one credential-census line suffices; the ADR-241 D1 line classifying `RESEND_API_KEY` is kept (P7).
- Header copy of the downtime table → duplicates the runbook and drifts; one pointer line only.

**Deferred with tracking (filed in P7, from spec-flow review; each is a gap in the already-shipped modes, not a regression of this work):**

- D6 precondition accepts a stale or superseded rotate (no age bound, skips later failed rotates).
- `mode=redeploy` has no readback although it is the recovery path after `RECOVERY_FAILED`.
- A queued rollback can be dropped by a newer dispatch (the `git-data-state` group holds one pending run); document in the runbook, decide on a workflow-level notify later.
- Flip resume arm B leaves the flag true with no `flag_written` marker if the readback then fails.
- Re-drive of erasures refused during freeze/rotate windows, with the Art. 12(3) clock (cross-reference #9153).

**Open issue state (re-read 2026-10-02):** #8609 OPEN (PR-A and fix-forward #9314 merged; runtime key still branch-reachable; ADR-241 D2 `proposed`); #8209 OPEN (O10 done; O11–O13 listed open; #9361, #9362 and the entrypoint-audit dispatch open); #8620 OPEN (decision due at the fresh git-data replace); #8573 OPEN; #9066 OPEN with code merged and a 2026-10-24 CLO re-ruling deadline; #9395 OPEN; #9394 OPEN.

**Plan-review outcome (2026-10-02, 7 reviewers).** Applied as mechanical: output design corrected (the `freeze_held` marker is touched before the freeze and never cleared, so it cannot be exported); notify job needs a checkout and an `if:` that also fires on a failed probe; existing census rows named for update; AC-1 defined from the module's `file()` payloads; Guard 1 and Guard 2 mutation rows fixed; P5 corrected to a derived assembly. Applied as scope decisions, surfaced for the user: the three-way slicing above, P3 resolved to a probe that fails the run red after unwind (CPO condition 1) in place of the verdict-only default, a notify channel that cannot go silent (CPO condition 4), and the per-id re-erasure / positive-replication blockers named (CPO condition 3). DHH-style and simplicity reviewers advised deferring P3 or using a dispatch-only probe; the CPO condition recorded on #8211 ("the rollback rehearsal runs a successful erasure") is a product requirement, so P3 is kept.

**Institutional learnings applied:**

- `knowledge-base/project/learnings/2026-08-20-the-channel-was-silent-on-the-path-it-was-built-for.md` — a guard about ORDER/LIFETIME needs a reorder row and a case observing inside the window.
- `knowledge-base/project/learnings/2026-09-18-every-mechanism-was-validated-against-the-tree-before-its-own-backfill.md` — validate each mechanism against the tree its own remediation produces; assert counts moved, not just exit 0.
- `knowledge-base/project/learnings/workflow-patterns/2026-07-19-real-cutover-routes-to-workflow-dispatch-and-failclosed-gate-must-self-report.md` — a fail-closed gate must report its own evidence; the real run is a gated dispatch.
- `knowledge-base/project/learnings/2026-04-14-parallel-review-resolvers-and-observability-races.md` — write run-state after the lock, unique sentinel per run (finalizer markers).
- `knowledge-base/project/learnings/2026-03-11-multi-platform-publisher-error-propagation.md` — graceful degradation that returns 0 loses the signal; the notify path must not swallow its own failure.
- `knowledge-base/project/learnings/2026-03-21-ci-terraform-plan-workflow.md` — mask fetched secrets, randomized heredoc delimiters in `GITHUB_OUTPUT`.

## User-Brand Impact

**If this lands broken, the user experiences:** an Article 17 "Delete Account" that is refused or silently incomplete because a failed flip left `/mnt/git-data/.cutover-freeze` in place with nobody notified, or a flag that disagrees between web hosts so one host stops replicating commits.

**If this leaks, the user's source code / workflow is exposed via:** a mis-scoped `prd` flag-write credential or a notify path that carries workspace identifiers; this work adds no credential and its notify body carries only the run URL, role names and verdict words, never workspace ids or free-text inputs.

**Brand-survival threshold:** single-user incident

CPO sign-off: **sign-off with conditions** (2026-10-02 plan review); the conditions are folded into P2, P3, P7 and the acceptance criteria below. `soleur:engineering:review:user-impact-reviewer` runs at review. Reason for the threshold: the surface guards the one store holding every user's repositories and the erasure path; one stuck freeze is one user's account erased on paper and not in fact.

## Authorization-gated sequence (documented, NOT dispatched by this plan)

Every step below runs through an existing reviewer-gated workflow or a Terraform apply and needs the user's explicit per-step authorization (`hr-menu-option-ack-not-prod-write-auth`). Nothing here is dispatched by the pipeline.

1. #8609 R-steps (R3 onward unblocked per its 2026-09-30 comment), then ADR-241 D2 → `accepted`.
2. #8209 O11–O13 residue, #9361 (marketplace bypass actor swap), #9362, the entrypoint-audit dispatch.
3. #8573 credential: defined in Terraform per the #8209 / ADR-241 design (a `prd`-scoped token delivered as an environment secret), scoped to the `GIT_DATA_STORE_ENABLED` write only, windowed, with the one-token-or-two decision recorded. A presence preflight that fails before any freeze begins is part of this step.
4. `git-data-host-rotate` (`confirm=ROTATE-GIT-DATA`): fresh host plus `GIT_DATA_LUKS_KEY` rotation immediately before the flip. This is also git-data's root-disk rebuild window, so the #8620 decision (boot an encrypted root, or record in the ledger row why not) is taken here.
5. Flip-readiness preconditions recorded by this work: the git-data host off-host liveness signal (the new P7 issue) is live; a flip-then-rollback rehearsal has run once with the erasure probe passing and its run URL is recorded (CPO condition 2).
6. The #9066 lock purge runs inside the flip's freeze window; the CLO deadline is 2026-10-24.
7. `mode=flip` (`confirm=FLIP-GIT-DATA`), from `main`, environment approved; `mode=rollback` stays available throughout.
8. Downtime for steps 4 and 7 is stated in P4 so the reviewer reads it before approving.

## Implementation Phases

### PR-A — cutover hardening

#### P1 — Pin the readback host set to `var.web_hosts` (property 2)

- The readback loop in `.github/workflows/git-data-cutover.yml` needs a per-host container-name map that the IP list does not carry, so keep the literal and add a key operand to `apps/web-platform/infra/web-hosts-fanout-parity.test.sh`: it extracts the readback host names and compares the set to the `var.web_hosts` **keys**. The suite today extracts `private_ip` values only and hardcodes `VARS_TF` and `CUTOVER_WORKFLOW`, so P1 adds env seams (as `GDC_WORKFLOW` does in the access suite) and a second floor.
- Failing case: a third host added to `var.web_hosts` without a readback entry turns CI red.

#### P2 — A notify job that cannot go silent (property 4; CPO condition 4)

Outputs (corrected after review): the existing `freeze_held` file marker is touched at `git-data-cutover.yml:415` before the freeze runs and is never cleared, so exporting it would flag a stranded freeze on every clean unwind. Instead:

- Give the finalizer step `id: finalizer`. It writes `freeze_held=1` to `$GITHUB_OUTPUT` **only** in its unfreeze-FAILED branch (~line 599) and `recovery_failed=1` **only** in its `RECOVERY_FAILED` branch (~line 609), each **before** its `exit 1`. Add `unfreeze_failed`/`recovery_failed` equivalents for `mode=unfreeze` and for the rollback's trailing unfreeze (today `|| true`), set from the real exit code in every mode. **Deferred (work phase):** making `nothing_to_rollback` report a held sentinel needs host access, and that path skips the bridge by design; it is tracked in the follow-up issue, not built here.
- Map these to `jobs.cutover.outputs:` together with `mode`, `started` (a step output set at the first step, so a reviewer rejection is not mistaken for a failed cutover) and `probe_failed` (P3).

The job:

- `notify-failure`: `needs: cutover`, `permissions: contents: read` plus `issues: write` (for the issue channel below), `timeout-minutes: 5`, **no `environment:`**, **no `concurrency:`** (it must not queue behind `web-1-swap` holders), a pinned `actions/checkout` step before the local `./.github/actions/notify-ops-email` (the composite does not resolve without it; `infra-validation.yml` `notify-main-failure` is the precedent).
- `if: always() && (needs.cutover.result == 'failure' || needs.cutover.result == 'cancelled') && needs.cutover.outputs.started != 'false'` (final form after code review). Not the broader `!= 'success'`: skipped runs must not email. `started` is `false` only when the confirm step ran and rejected the input (a typo'd token, a bad mode: nothing changed, stay quiet); an ABSENT output (runner loss, a rejected approval) pages, because "no output" is the state this job exists to report. The `probe_failed` disjunct was dropped from the `if:` (the probe step has no `continue-on-error`, so a probe failure is already `result == 'failure'`); `probe_failed` stays as the PROBE_FAILED word.
- Channel: file or update a `ci/git-data-cutover` GitHub issue (primary, the `workspaces-luks-verify` pattern) **and** send the ops email (secondary, `continue-on-error`). The `::error` annotation stays. A missing `RESEND_API_KEY` degrades to issue-only and is itself named in the issue; reconcile the Observability wording with this (no "best-effort yet fail-loud" contradiction).
- Body: run URL, mode, role names, verdict words, the lineage `cutover-<run_id>`, and — when outputs are absent (timeout or runner loss) — the line `STATE UNKNOWN: check the flag, the freeze sentinel and both hosts`, plus the exact remedy line (`mode=unfreeze lineage=cutover-<run_id>` for a held foreign sentinel). **Never** interpolate `inputs.lineage` or any free text into the body.
- Keep the `::error` lines; reconcile the stale header wording at `git-data-cutover.yml:29` with what is wired.

Existing census edits this forces (listed so they are not discovered red): `WF-jobs` (exactly one job today), `WF9` secret set (add `RESEND_API_KEY`), the `AC9` row requiring `local == [BRIDGE]` (the new local action), the `_wf_n >= 38` floor, and `wr_sites` (iterates `job["steps"]` only — extend it to every job).

#### P3 — Rollback proves erasure still works (property 7; CPO condition 1)

- After `mode=rollback` completes its unfreeze and gc restart, run the existing `MODE=probe` (transactional provision → CAS-fenced push → remove → zero-residue) as a step **gated on the unfreeze step having succeeded** (a still-held sentinel would make the host refuse provision and misreport a stranded freeze as an erasure failure). Rollback's own actions are unchanged and have already completed; a failed probe then fails the run **red** and sets `probe_failed=1` so P2 notifies. The reason is that the probe runs after recovery, so failing the job cannot block anything.
- The existing `WF-gating` rows ban `continue-on-error` and require exactly one `MODE=probe` step with a mode/flag_precheck-shaped `if:`; widen that step's `if` to `flip || rollback` (one step, not two) and amend the rows explicitly.
- The notify body names `residue_left` when the probe leaves synthetic residue (it keeps `served_repos>0` and blocks the next rotate).
- The pre-flip flip-then-rollback rehearsal (CPO condition 2) is recorded in the runbook as a flip precondition with a place for its run URL; it is performed only under the user's authorization.

#### P4 — Downtime statements (property 6, `hr-prod-host-config-change-immutable-redeploy`)

- Add one "Downtime and blast radius" table to the runbook (`knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`, next to the G3 statement at ~line 808) for `flip`, `rollback`, `redeploy` and `git-data-host-rotate`; the workflow header carries a single pointer line.
- Numbers are **measured, not asserted** and measurement is a merge gate: same-version redeploy duration from recent `deploy-status` frames and release runs; the web-1 container restart window (web-1 is the singleton ingress per ADR-143 D2; web-2 is a standby outside the ingress rotation); git-data untouched by flip/rollback/redeploy but destroyed and rebuilt by rotate.
- User-visible statement (CPO condition 6): what a user sees while a deletion is refused during freeze, rotate or rollback windows, that the refusal is a logged Art. 17 event, that refused ids are swept and re-driven, and the Art. 12(3) one-month clock; cross-reference #9153.

#### P7 — Records and tracking (no code)

- ADR-241: a one-line D1 amendment classifying `RESEND_API_KEY` as Tier A (send-only; reads no other tier; no infra write), plus the workflow header's credential census line.
- GitHub: update the #8211 body checklist (strike moot items with the reason; make it an umbrella with explicit successor issues); comment on #8573 with the single-token vs two-token discrepancy and the interface the workflow consumes, and request an owner and milestone there; comment on #8571 and #8093 with the re-evaluation notes; file the new issue "git-data host: recurring off-host liveness signal (no Vector, last boot_complete 2026-09-25)" with a milestone, bundled with #8093's next template change and **recorded as a `mode=flip` precondition**; file the deferred items listed under Research Insights as one tracking issue each or one grouped issue with a checklist. State, for the per-id re-erasure path and positive replication evidence named in the #8211 comments, whether each is built or a named flip blocker with an owner (CPO condition 3). `wg-when-deferring-a-capability-create-a`.

### PR-B — bound the remaining in-container apt cycles (P5, #9395)

- `apps/web-platform/infra/git-data-cutover-access.test.sh` (loop at ~2652-2661): source `lib/apt-bounded.sh` (`. /work/apt/apt-bounded.sh || exit 97`, `gd_apt_install_bounded <pkgs> || exit $?`, `gd_apt_state_arm`, mount it), keeping `_runtime_skip` fail-closed under CI and the exact assertion floor (#8744). #9394 stays undecided: no arm may begin to skip.
- `apps/web-platform/infra/cloud-init-inngest-provision-unit.test.sh` (Tier B, ~1418): same helper. The container's `sh -c` is dash and `lib/apt-bounded.sh` needs bash (`BASH_SOURCE`, `local -a`), so convert to `bash -c`; the call site is `if ! docker run …`, a form the helper test's docker regex does not match today.
- `apps/web-platform/infra/apt-bounded.test.sh`: the A10 assembly row is a fixed list (`OWN`, `REH`, `_tot -eq 6`), not a scan, so a third suite would go undetected. Make it glob-derived over `*.test.sh`, widen the docker regex to the `if ! docker run` form, and recount the floors (including the `19`) after the edit; do not hand-carry numbers.

### P6 — #9066 closeout (CLO deadline 2026-10-24; standalone)

- Verify, by reading the merged code, that provision and remove use the constant `.init.lock` and that `mode_freeze` purges the legacy `.<id>.init.lock` files; confirm the purge publishes a **count only** and excludes `.boot-probe-0.init.lock`.
- If the plaintext volume's retention end is not stated, add it to ADR-239 (dated amendment) and the runbook; never mount that volume to purge in place.
- Leave the issue OPEN: it closes only after the purge has run in a real flip window. Comment with what is verified, each claim backed by a file:line.

## Files to Edit

PR-A:

- `.github/workflows/git-data-cutover.yml` (P2, P3, header pointer)
- `apps/web-platform/infra/web-hosts-fanout-parity.test.sh` (P1)
- `apps/web-platform/infra/git-data-cutover-access.test.sh` (P2/P3 census rows listed above)
- `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md` (P3 rehearsal precondition, P4)
- `knowledge-base/engineering/architecture/decisions/ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md` (P7, one line)

PR-B:

- `apps/web-platform/infra/git-data-cutover-access.test.sh`, `apps/web-platform/infra/cloud-init-inngest-provision-unit.test.sh`, `apps/web-platform/infra/apt-bounded.test.sh` (P5)

P6: `knowledge-base/engineering/architecture/decisions/ADR-239-git-data-serves-from-luks-at-birth.md` and the runbook, only if the retention end is missing.

`git-data-cutover.sh` is **not** edited: it runs on CI, is not in the hash-bound set (AC-1), and the P3 probe reuses its existing `MODE=probe`.

## Files to Create

- `knowledge-base/project/specs/feat-8211-git-data-real-modes/tasks.md` (derived from this plan)

Verified: each path exists on `origin/main` (`git ls-files`); no glob prescribed.

## Open Code-Review Overlap

None. (Ran `gh issue list --label code-review --state open` and matched every file above, plus the ADRs and the runbook, by path: zero hits.)

## Acceptance Criteria

### Pre-merge — PR-A

- [ ] AC-1: no hash-bound payload changes. The hash-bound set is what `git_data_rung2_bound_files apps/web-platform/infra/cloud-init-git-data.yml` prints after `source tests/scripts/lib/git-data-birth-readiness-gate.sh` (17 files on 2026-10-02); `git diff --name-only origin/main...HEAD` intersected with that output is empty (measured empty at the work-phase commit), and `git-data-rung2-rehearsal.test.sh` passes in CI.
- [ ] AC-2 (P1): adding a third `var.web_hosts` key without a readback entry makes `web-hosts-fanout-parity.test.sh` fail (via the new env seams); the current tree passes.
- [ ] AC-3 (P2): `notify-failure` exists with the `if:` above, no `environment:`, no `concurrency:`, a checkout step, `permissions: contents: read` + `issues: write`, `timeout-minutes: 5`, and `RESEND_API_KEY` bound only there; the updated census rows pin all of it.
- [ ] AC-4 (P2): `freeze_held`/`recovery_failed`/`probe_failed`/`started` are job outputs set only on the failure branches; a clean unwind and a clean flip emit none of them (census rows over the finalizer step).
- [ ] AC-5 (P2): the notify subject and body contain no workspace id and no interpolation of `inputs.lineage`; a cancelled run with no outputs says `STATE UNKNOWN` and prints the lineage and the exact unfreeze remedy line.
- [ ] AC-6 (P3): a rollback run runs the probe once its unfreeze succeeded; a forced probe failure fails the run red after unwind and notifies; the rollback's own exit code path is untouched. (`nothing_to_rollback` with a held sentinel is deferred to the follow-up issue.)
- [ ] AC-7 (P4): the runbook carries a downtime table for flip, rollback, redeploy and rotate, each number citing its measured source, plus the user-visible deletion-refusal statement; the header carries only a pointer.
- [ ] AC-8 (P7): ADR-241 D1 line, GitHub comments and the new issues exist (observability issue with milestone and flip-precondition marker; deferred-items issue(s); #8573 owner request); the #8211 checklist is updated; PR body says `Refs #8211`.
- [ ] AC-9: the full CI matrix is green (the full local battery runs only on request; CI owns it).

### Pre-merge — PR-B

- [ ] AC-10: both suites call the bounded helper under `bash -c`; the glob-derived assembly row fails when either suite (or a new third one) reintroduces a bare attempt-count apt loop; floors recounted; `_runtime_skip` still fails under CI; CI green.

### P6

- [ ] AC-11: the #9066 comment's code claims each cite a file:line; the retention end is stated in ADR-239 and the runbook.

### Post-merge (authorization-gated, not dispatched here)

- [ ] The Authorization-gated sequence above, each step separately authorized.

## Guard Contract

### Guard 1 — Readback host-set parity

**Property.** Every host in `var.web_hosts` appears in the per-host `git_data_store=` readback, so no host can be left unread after a flip or rollback.

**Assembly.** The readback loop literal in `git-data-cutover.yml`; the `var.web_hosts` keys in `variables.tf`; the redeploy and finalizer list (`WEB_HOST_PRIVATE_IPS`); any other host loop in the workflow (grep `for h in` and `WEB_HOST_PRIVATE_IPS`). The chokepoint is the parity suite, which extracts each copy by shape and compares sorted sets, through env seams for the workflow and `variables.tf` paths so a mutant fixture can be fed in.

**Mutation matrix.**

| # | Edit | Must |
|---|---|---|
| 1 | add `web-3` to the fixture `variables.tf` only | RED |
| 2 | remove `web-2` from the fixture readback loop only | RED |
| 3 | break the extractor so it matches zero loops (dispatch row) | RED (floor), not "0 checked, exit 0" |
| 4 | reorder the loop entries | GREEN (set equality) |

**Harness rows.** Edit the suite to compare counts instead of sets: row 1 must still go RED. Must-PASS non-canonical input: the same hosts in a different order with extra whitespace.

**Anchor.** The `var.web_hosts` side lives in `variables.tf`, independent of the workflow and the suite, so editing those two together cannot hide a roster change.

### Guard 2 — Notify/finalizer coverage and scope

**Property.** A failed, stranded or cancelled cutover (and a failed rollback probe) always reaches the notify path, a clean run never does, and the path carries no workspace id and no privileged credential.

**Assembly.** Every job in `git-data-cutover.yml`; every step with `if: always()`; every `secrets.*` binding across **all jobs** (the census currently scans `job["steps"]` of one job); the finalizer's `$GITHUB_OUTPUT` writes; the notify job's `if:`, `needs:`, `permissions:` and `uses:`.

**Mutation matrix.**

| # | Edit | Must |
|---|---|---|
| 1 | delete the notify job | RED |
| 2 | drop `always()` from its `if:` | RED |
| 3 | change its condition to `failure()` only (cancelled and probe-failed no longer notify) | RED |
| 4 | add `environment: web-platform-infra-apply` to it | RED (credential scope) |
| 5 | bind `DOPPLER_TOKEN_GIT_DATA_FLAG` in it, after a compliant `RESEND_API_KEY` binding | RED |
| 6 | interpolate `inputs.lineage` or a workspace id into the body | RED |
| 7 | have the finalizer write `freeze_held=1` on its success path | RED (clean unwind must not notify) |
| 8 | widen the notify `if:` to `!= 'success'` | RED (skipped runs must not email) |

**Harness rows.** Edit the census extractor to read only the first job: row 5 must still go RED. Must-PASS non-canonical input: a notify job with `with:` keys reordered, which the contract permits.

**Anchor.** A merge-base diff of the census binding list; a changed binding set needs the CTO's sign-off on the PR, not just a suite edit.

### Guard 3 — In-container apt cycles are time-bounded (PR-B)

**Property.** No in-container apt cycle in an infra test suite is bounded by attempt count alone.

**Assembly.** Every `apt-get`/`apt` use inside `docker run` blocks (including the `if ! docker run` form) across `apps/web-platform/infra/*.test.sh`, found by glob rather than a fixed list; the helper `lib/apt-bounded.sh`.

**Mutation matrix.**

| # | Edit | Must |
|---|---|---|
| 1 | reintroduce the bare attempt loop in `git-data-cutover-access.test.sh` | RED |
| 2 | reintroduce it in `cloud-init-inngest-provision-unit.test.sh` (the `if ! docker run` form) | RED |
| 3 | add a third suite with a bare loop after two compliant ones | RED |
| 4 | make the glob match nothing (dispatch) | RED (floor) |

**Harness rows.** Edit `apt-bounded.test.sh` to scan only the two named files: row 3 must still go RED. Must-PASS non-canonical input: a suite calling `gd_apt_install_bounded` with a different package list.

**Anchor.** Merge-base count of apt cycles per suite, asserted with set identity (file names).

## Observability

```yaml
liveness_signal:
  what: git-data-cutover run results and the notify-failure job outcome
  cadence: per dispatched run (user-triggered, not scheduled)
  alert_target: a ci/git-data-cutover GitHub issue (primary) and ops@jikigai.com via notify-ops-email (secondary), plus the run's ::error annotations
  configured_in: .github/workflows/git-data-cutover.yml (notify-failure job)
error_reporting:
  destination: GitHub issue + ops email carrying verdict words FREEZE_HELD, RECOVERY_FAILED, residue_left and probe verdicts
  fail_loud: the issue channel is primary so a Resend outage or missing RESEND_API_KEY degrades to issue-only and is named in the issue
failure_modes:
  - mode: freeze sentinel left held after a dead git-data hop
    detection: freeze_held output set only in the finalizer's unfreeze-FAILED branch
    alert_route: notify-failure issue and email
  - mode: partial unwind (flag, redeploy or off-lines incomplete)
    detection: recovery_failed output set only in the RECOVERY_FAILED branch
    alert_route: notify-failure issue and email
  - mode: rollback completed but the erasure probe failed
    detection: probe_failed output; run fails red after unwind
    alert_route: notify-failure issue and email
  - mode: runner loss or 120-minute timeout mid-window
    detection: needs.cutover.result is cancelled or failure with no verdict outputs
    alert_route: notify-failure issue and email carrying STATE UNKNOWN and the lineage
  - mode: a web host omitted from the readback
    detection: web-hosts-fanout-parity.test.sh in infra-validation
    alert_route: red CI check on the PR
logs:
  where: GitHub Actions run logs; Better Stack git_data_store= lines from each web host
  retention: GitHub default run-log retention; Better Stack plan retention
discoverability_test:
  command: grep -n "notify-failure" .github/workflows/git-data-cutover.yml
  expected_output: notify-failure
```

The git-data host itself stays dark between boots (no Vector); the new tracking issue in P7 owns that gap and is a `mode=flip` precondition.

## Domain Review

**Domains relevant:** Engineering, Legal, Operations, Product

### Engineering

**Status:** reviewed (CTO, architecture-strategist, Kieran, DHH-style, code-simplicity, spec-flow; 2026-10-02)
**Assessment:** the re-scope is right; findings applied above (slicing, output design, notify scoping, census edits, hash-bound definition). ADR-241 tiering: a repo-secret `RESEND_API_KEY` in a notify job without `environment:` fits (precedent `notify-root-key-apply`); recorded as a one-line D1 amendment.

### Legal

**Status:** carried forward (no fresh spawn)
**Assessment:** the CLO ruling on #9066 stands (completeness gap against DPD §10.3(b), Art. 5(1)(c) and (e); fix and purge before the first flip; re-rule if past 2026-10-24). This work adds no new processing and touches no schema, auth flow or API route; GDPR gate triggers (a)–(d) do not fire. The notify body carries no workspace identifiers (AC-5). User-visible refusal-window statement and Art. 12(3) clock added to P4.

### Operations

**Status:** reviewed via CTO/spec-flow; runbook downtime table (P4) and the authorization-gated sequence are the deliverables.

### Product

**Status:** reviewed (CPO — sign-off with conditions)
**Tier:** none (no UI surface; no UI path in Files to Create or Edit). The CPO's seven conditions are folded in: P3 red-after-unwind (1), pre-flip rehearsal as a recorded precondition (2), per-id re-erasure and positive-replication blockers named (3), non-silent notify channel (4), observability issue as a flip precondition (5), user-visible refusal-window statement (6), P5 split out (7).

## Test Scenarios

- Parity suite: add, remove and reorder host entries (Guard 1 matrix).
- Census suite: notify job present, scoped, `always()`-conditioned, outputs set only on failure branches, binding set (Guard 2 matrix).
- Finalizer states: clean flip, clean unwind, failed unfreeze, partial unwind, `mode=unfreeze` failure, rollback with `nothing_to_rollback` and a held sentinel.
- Rollback probe: passes; forced failure fails red after unwind and notifies; a held sentinel skips the probe rather than misreporting it.
- apt-bounded assembly: bare-loop reintroduction fails (Guard 3 matrix).
- `actionlint` clean on the touched workflow; `bash -n` on touched scripts.

## Risks and Sharp Edges

- A notify job without `environment:` emails on a rejected approval or a branch dispatch that fails the environment policy; the `started == '1'` clause is what keeps those quiet. Test that clause directly.
- Job outputs are absent on timeout or runner loss; the notify body must therefore treat "no outputs" as `STATE UNKNOWN`, not as clean.
- Any edit that strays into a hash-bound payload voids the rung-2 evidence and holds the next replace or rotate (AC-1).
- P4 numbers must be measured from real frames; an asserted downtime is worse than none, and measurement gates the merge.
- #9066's 2026-10-24 deadline is outside this work's control: the purge only runs inside a real flip window, which needs the gated steps first. If the chain slips, the CLO must be told before the date, not after.
- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6; this one declares `single-user incident` and carries the CPO's conditional sign-off.
- #9394 is deliberately untouched: P5 must not make any apt arm skip.

## Code-Review Outcome (2026-10-02/03, 11 seats at 34f10250b9)

Structural-cause roll-up: **(1)** the census pinned the SPELLING of a workflow whose finalizer, notify body and `if:` were never executed (test-design, structural-enumeration, code-quality, architecture seats); **(2)** the notification labelled known states "STATE UNKNOWN" and printed an unconditional remedy (agent-native, code-quality, pattern, security, architecture, user-impact, data-integrity seats). Both fixed at the class level, not per instance.

Fixed inline: the finalizer now exports `ran=1` (so a failed run with a finalizer reads as FAILED and only a missing output reads as STATE UNKNOWN), exports `freeze_held` for a failed `mode=unfreeze`, and skips its redundant rollback unfreeze when the rollback's own unfreeze succeeded (a good rollback can no longer go red on it); the notify `if:` uses `started`; the body is result-aware, the remedy prints only for stranded or unknown states, names the WRITER's lineage and `--ref main`; the issue step fails open (a failed lookup files a new issue), filters by author and records the email outcome; checkout is `persist-credentials: false`; the census compares whole expressions and key sets, scans every job and every `secrets` token form, pins the issue and email steps; the finalizer and the notify body are EXECUTED in 21 cases and mutation-proven (nine executed mutants, six wiring mutants); the parity suite reads block-scoped, multi-line and underscore keys and carries a row floor; C4 `model.c4` (two edges) and ADR-239/ADR-241 amended; the runbook qualifies the erasure re-drive claim, the probe's scope, the gaps below and the PROBE_FAILED recovery (`mode=proof`).

Deferred to the tracking issue (each needs host access or a new mode, so it is not inline-sized): a rollback that finds the flag already off (`nothing_to_rollback`) does not read a held sentinel; no finalizer cleanup of a synthetic repository left by a failed or cancelled probe; no standalone probe mode (a re-dispatched rollback exits `nothing_to_rollback`); a force-cancel and a pending run replaced in the `git-data-state` group notify nobody; `provision` failing on a booting host reads as PROBE_FAILED; flip dies between the flag write and its marker (flag may stay true with no unwind); rollback has no per-host readback in the finalizer; a failed `gc.timer` restart only warns; the dead `UNFREEZE`-mode wiring for Art. 17 re-drive after a stranded freeze (#9153). The probe proves the host wrapper contract only; the app-path erasure signal is a rehearsal precondition (runbook).
