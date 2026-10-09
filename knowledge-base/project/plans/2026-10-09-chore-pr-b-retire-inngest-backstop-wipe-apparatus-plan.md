---
title: "PR B: retire the Inngest backstop wipe apparatus and converge the records (#8285, also #6894)"
date: 2026-10-09
slug: pr-b-retire-inngest-backstop-wipe-apparatus
branch: feat-one-shot-8285-6894-pr-b-retire-wipe-apparatus
issue: 8285
refs: [8285, 6894, 8316, 9703, 9786, 9879, 8620, 6897, 9877, 9784]
closes: []
type: chore
priority: p2-medium
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
draft_pr: 9877
---

# PR B: retire the Inngest backstop wipe apparatus and converge the records

Spec lacks valid lane: no `spec.md` exists for this branch, so `lane` defaulted to `cross-domain` (fail-closed).
`requires_cpo_signoff` is carried from PR A's plan (same decision, no new approach chosen here).

PR bodies, titles and every commit message use `Ref #8285` / `Ref #6894` only. No closing keyword appears next to
either number anywhere. The trackers are closed after merge with an explicit `gh issue close` (see Phase 8).

## Overview

PR A (#9784, merge `d7dee46bb0e80a6ea056e0dd4795d32508d4bc51`) built the gated retirement apparatus for the
plaintext Redis AOF backstop `hcloud_volume.inngest_redis` (Hetzner id 106261946). All three production phases
have since run and succeeded on 2026-10-09: `detach` (run 37950928039), `wipe` (run 37955244979, which also tore
the wipe host down) and `destroy` (run 37958051426: `GET /v1/volumes/106261946 -> 404 at 2026-10-09T16:21:26Z`,
server volumes `[106903269]`, Terraform `Apply complete! 0 added, 0 changed, 1 destroyed`). The volume is gone.

PR B is the convergence PR. It deletes the apparatus that has nothing left to act on, retires the one dispatch verb
that can no longer work (`op=luks-rollback`), removes the ledger row for a resource that no longer exists,
completes the Art. 5(2) destruction record from the evidence, and brings every dated register, ADR and runbook in
line. **It makes no hand-written production change.** Merging it triggers two routine automations that are not
retirement actions: the per-merge Terraform apply (`apps/web-platform/infra/**`; expected plan: no changes,
because the wipe resources were already destroyed and the orphans are gone from state) and the container release
(`apps/web-platform/**`). Neither touches the Inngest store. PR B's body states that on its first line.

**Deadline.** The ledger row expires 2026-10-22 and is non-extendable; from that date
`lint-encryption-posture.py` fails every PR repo-wide. Removing the row requires this PR, so PR B merges by
2026-10-21. Target merge 2026-10-13 to leave room for the Phase 7 review loop and the merge queue.

## Research Reconciliation: spec/brief versus codebase

| Brief or task-list claim | Reality (verified 2026-10-09) | Plan response |
|---|---|---|
| Tasks 3.4: delete the property probe, its test and the `run_suite` line; brief step 4: keep them until #9703 is armed | The probe is enrolled by a `soleur:followthrough` directive in **#8285's body**; the sweeper stops running it the moment #8285 closes (probe header RETIREMENT paragraph; #9703 body says the same). Brief step 6 ends tracker 8285 after merge. | D4: keep the files, **re-home the directive to #9703** so the daily silent-pipeline report survives #8285's closure; delete only when #9703 arms. |
| Retire `op=luks-rollback` in workflow + orchestrator | The on-host FSM `rollback)` arm in `inngest-luks-cutover.sh` ships in the baked image; editing it needs an image release, pin bump and host replace (ADR-142 addendum 2026-10-08 rejected exactly that for the wipe). PR A already pinned its refusal (`rollback-no-backstop`, fixture in `inngest-luks-cutover.test.sh`). | D3: retire the dispatch side only; leave the baked arm; record the dead on-host arm on #9786 (next planned replace). |
| The probe's test is untouched by retiring the verb | `inngest-luks-property-8296.test.sh` carries a whole "AC-32 rollback NEXT placement" block that extracts the `luks-cutover\|luks-rollback)` arm of `scripts/cutover-inngest.sh` and its `NEXT (not automatic)` line, plus a hard `MIN_PASSES=122`. It also asserts the runbook heading `^## 5a\. .*op=luks-rollback`. | Phase 2 edits the probe **test** (not the probe script): drop the AC-32 block, lower `MIN_PASSES` with an itemised comment, and keep a 5a heading that still matches. |
| Delete the retire job: only the job and its gate need changing | `apps/web-platform/infra/inngest-redis-luks.test.sh` G4.b2 requires the retire dispatch's pointer reader exactly once (`_g4_retire_read`). `scripts/lib/inngest-probe-row.test.sh` has an ALLOW entry for the gate lib. `test-infra-privileged-tier-census.sh` `INTENDED_DESTROYS` carries two entries its own comment says to drop in PR B. `infra-credential-tiers-8209.md` has a job row. | Phase 1 handles each; the closing census is by identifier, not name (learning 2026-09-27). |
| `compliance-posture.md` "row" to amend | The file has **no** existing Inngest backstop row (`grep -i "luks\|aof\|plaintext"` finds none). | Phase 5 adds a Completed Compliance Work row, modelled on the #8734 deletion row (line "Retained unencrypted root-disk snapshot ... CLOSED on deletion"). |
| Attach/detach times come from Hetzner "action history" | `GET /v1/volumes/106261946/actions` still answers **200** after the delete (measured 16:45:52Z). | Fields are fillable (Research Insights table). No fallback to run logs needed. |
| Wipe-row `dt` is Better Stack's receive time, or the host's clock: unmeasured | Measured now: top-level `dt` = `2026-10-09 16:04:25.000000` equals the body's own `"dt":"2026-10-09T16:04:25Z"` (whole seconds); `ingest_time` = `2026-10-09 16:04:25.889296`. | Recorded in the destruction record: `dt` is the sender's clock; `ingest_time` is the receive time and is the column the window check should have read. |
| `betterstack-logs-alerts.tf` `incident_cause` must be reworded | It reads "volume that is NOT the encrypted one ... Redis writes are landing unencrypted": true with or without the backstop. Changing it is an in-place Better Stack update applied by the merge's apply. | D6: leave `incident_cause` and the query unchanged; reword **comments** only. |
| `apply-web-platform-infra.yml` is close to its size gate | 489,495 bytes against `WORKFLOW_FILE_GATE_BYTES = 490,000` (505 bytes of headroom). The retire job is ~407 lines. | The deletion is what restores headroom; no hunk may add net bytes (AC). |
| #8316 (retire-or-keep the recut target) | The recut job was already converted and removed by PR A; what remains is `inngest_host_dark_gate`, kept as a suite-only entry point (shared helpers feed `inngest_execute_registry_gate`). Two stale comments in files this PR edits (`cutover-inngest.yml` G3.7 text, `cutover-inngest.sh` "recut via the inngest-host-replace window") are on #8316's list. | D10: fold the two comment fixes in; re-scope #8316 to the suite-only entry point and keep it open. |

### Premise validation (Phase 0.6)

Checked by command: #8285 and #6894 are OPEN; #8316, #9703, #9786 and #8620 are OPEN; PR #9784 merged at
2026-10-09T14:11:00Z as `d7dee46bb0` (ancestor of main); the three runs are `success`, dispatched from `main` by
`deruelle`, each approved in environment `inngest-cutover` by `deruelle` (`gh api .../actions/runs/<id>/approvals`);
run `headSha` for all three is `32b2fe2abb` (main's tip then; it contains the job). Hetzner re-read at
2026-10-09T16:45:52Z with the read-only token: volume 404; `servers/169426216.volumes == [106903269]`;
volume list has six volumes, 106261946 absent; no server labelled `role=inngest-backstop-wipe`. Scheduled drift
run 37891275302 (06:00Z) is green and predates the destroy; the first post-destroy run is 18:00Z. Nothing cited
was stale. The proposed mechanisms (delete, ledger removal, record completion) are the ones ADR-142's
2026-10-08 addendum already decided; none sits in a rejected-alternatives table.

### Property List and Cut List (Phase 0.6b)

Properties PR B must give:

1. No dispatch, job, input, variable, Terraform file or test can still act on, or imply the existence of, the
   retired backstop volume or the throwaway wipe host.
2. `op=luks-rollback` cannot be dispatched, and no live document tells a reader it can.
3. The encryption-posture ledger and the Art. 30 register state the post-retirement truth, with the erasure claim
   worded exactly as strongly as the evidence supports ("logical, guest-side, self-attested").
4. The evidence for the destroy is copied into a durable record before Better Stack retention ages it out.
5. A silent probe pipeline stays reported until the replacement feeder (#9703) is armed.
6. Every repo-global ratchet moves down by exactly what was removed, and no retired surface can silently return.

Cut list (mechanism, property it would buy, what already covers it):

| Mechanism considered | Property | Already covered by / cut because |
|---|---|---|
| Keep a hard-retired stub job + enum option that exits 1 (the `workspaces-luks-recut` precedent) | 1 | GitHub rejects an unknown `choice` value at dispatch (loud); a stub costs bytes in a file 505 bytes from its gate. Cut (D2). |
| Edit the baked on-host `rollback)` arm | 2 | Needs image release + replace; arm already refuses with `rollback-no-backstop`. Cut (D3). |
| Delete `inngest_host_dark_gate` and its rows | 1 | Suite-only entry point sharing helpers with the live execute gate; larger refactor, its own battery. Cut to #8316. |
| Change the wrong-volume alert's `incident_cause` | 3 | Text is still true; edit forces a provider update. Cut (D6). |
| New follow-through for the dead on-host arm | 2 | Extend #9786 (next planned replace) with a comment. Cut a new issue. |
| `prevent_destroy` / `delete_protection` on `hcloud_volume.inngest_redis_luks` now that it is the sole copy | 6 | In-place update of a live volume applied by the merge's apply = a production write; and host replace legitimately replaces its attachment, so the web-1 pin set does not copy over. Deferred and tracked in #9879 (filed 2026-10-09). |

## Research Insights

### Evidence pulled at plan time (2026-10-09, read-only; counts and identifiers only)

All values below are copied so Better Stack's finite retention cannot lose them. The work phase re-pulls each and
uses these only when a re-pull is impossible, saying so.

| Field | Value | Source |
|---|---|---|
| Volume | 106261946, `soleur-inngest-redis-store`, ext4, hel1; `size_bytes=10737418240` | wipe row; Hetzner |
| `detach_volume` from live host 169426216 | started 2026-10-09T15:27:12Z, finished 15:27:18Z, success | `GET /v1/volumes/106261946/actions` (still 200 post-delete) |
| `attach_volume` to wipe host 169544191 | started 16:02:56Z, finished 16:03:10Z, success | same |
| `detach_volume` from wipe host | started 16:04:59Z, finished 16:05:05Z, success | same |
| `delete_volume` | started and finished 2026-10-09T16:21:24Z, success | same |
| First 404 | 16:21:26Z in the destroy run (comment on #8285); re-read 16:45:52Z at plan time | Hetzner |
| Wipe `started` row | `dt` 2026-10-09 16:03:16.000000, `ingest_time` 16:03:17.468257 | Better Stack `remote(t520508_soleur_inngest_vector_prd_3_logs)` |
| Wipe `wiped` row | `dt` 16:04:25.000000, `ingest_time` 16:04:25.889296; `result=wiped nonce=37955244979 volume_id=106261946 size_bytes=10737418240 readback=zero sig_after=none fs_uuid=a535548b-2c22-4b90-a522-1c1922bba674 last_write=2026-09-20T15:28:40Z` | same |
| Row emitter as received | `host=soleur-inngest-backstop-wipe`, `shipper=inngest-backstop-wipe`: the hostname pin held | same |
| On-host duration | 69 s (16:03:16 to 16:04:25 on the host's clock) for 10 GiB | rows |
| Window check | `ingest_time` 16:04:25.889Z lies inside attach-finish 16:03:10Z and detach-finish 16:05:05Z (slack 300 s either side not needed) | rows + actions |
| Run step times, wipe run | apply (create) 16:02:41-16:03:14; evidence poll 16:03:14-16:04:51; teardown 16:04:51-16:05:25; run 15:54:55-16:05:31 | `gh api .../actions/runs/37955244979/jobs` |
| Run times, detach / destroy | detach run 15:19:57-15:27:30; destroy run 16:17:35-16:22:00; Guard 4 PASS line at 16:20:45Z | `gh run view` |
| Terraform | CI pin 1.10.5 (`TERRAFORM_VERSION` in the run env); orphan `-target` experiment re-run on 1.10.5 matches 1.9.8 | run log; session |
| Authorizing reviewer, each phase | `deruelle` (state `approved`, environment `inngest-cutover`); dispatcher also `deruelle` | `gh api .../approvals` |
| Live store | newest `host_role=dedicated` probe `data_mount_devid=scsi-0HC_Volume_106903269`, `redis_active=active` | brief; re-pull in Phase 0 |

Not recoverable and recorded as such: the wipe host's by-id device name (the row does not emit it; the wipe
completing implies the path resolved inside the 300 s wait).

### Learnings applied

- 2026-10-09 measured-`dt` learning: a "column means X" claim is per emitter; the record states the measurement.
- 2026-09-27 retirement census: enumerate **identifiers** (id `106261946`, addresses, names, labels, flag values, the
  pointer name), not only names, then run the repo's own destroy/census guards against the deletion.
- 2026-09-24 follow-through retirement: the footprint is whatever `git grep <stem>` finds, including `*.tsv`
  manifests and mid-document runbook mentions; every hit needs a disposition before the deletion commit.
- 2026-10-05 / 2026-10-09 ratchet learnings: repo-global ratchets (credential-header baseline, grep-q-pipe guard
  ceilings, fixture-relative-assert baseline, `--changed` lints on baselined files) are invisible to file-selected
  suites; run them explicitly before the first commit.
- 2026-10-09 rollback-recipe learning: execute the Rollback section once in a scratch worktree before merge.

### Open code-review overlap

Query run 2026-10-09 (88 open `code-review` issues; two-stage `gh --json` then `jq --arg`):

- #9705 (dead-probe heartbeat evidence; names `betterstack-logs-alerts.tf` and `model.c4`): **Acknowledge.** This
  PR edits comments in the first and one element description in the second; the heartbeat feeder is #9703, not here.
- #7942 and #8659 (name `scripts/test-all.sh`): **Acknowledge.** This PR deletes two `run_suite` lines only.

### Skipped phases (stated, not implied)

Community discovery (no uncovered stack) and functional overlap (repo-internal retirement) were not run.
Network-outage and CWV gates do not fire. Plan review beyond this file's own reconciliation and the deepen pass is
recorded in the Enhancement Summary after deepen-plan. Taste decisions (D2, D4, D10) are in `decision-challenges.md`
of the spec directory.

## Scope Check

Every deliverable maps to an ask: items 1 to 6 of the brief map to Phases 1, 2, 3, 4, 5 and 8. Inferred items,
each justified: the probe-test edit and `MIN_PASSES` change (forced by retiring the arm it reads: Phase 2);
`inngest-redis-luks.test.sh` G4.b2 removal and the four "never untargeted" qualifier reverts (forced by deleting
what they name: Phase 1); the "stays retired" guard (Guard 1: prevents silent resurrection by conflict resolution);
the directive re-home (D4: satisfies brief step 4 given step 6). No split is warranted: the pieces share one
ratchet-ordering problem and one deadline.

## Decisions

- **D1. No operator hold.** Unlike the web-1 convergence, the evidence exists before this PR is written, so there
  is no draft-until-evidence phase. The 404 is re-read at work start and again just before ship; PR B is not
  marked ready if either read is not 404.
- **D2. Delete the `inngest-backstop-retire` enum option and job outright.** No exit-1 stub. A stale dispatch of a
  removed choice value is refused by GitHub before any job exists. (Taste, recorded in `decision-challenges.md`.)
- **D3. Retire `op=luks-rollback` on the dispatch side only.** Remove it from `cutover-inngest.yml` (header, choice
  list, both ternaries) and `scripts/cutover-inngest.sh` (case label and every `luks-rollback` branch). Leave the
  baked `rollback)` arm and its FSM comments; add a comment on #9786 listing them for the next replace.
- **D4. Re-home the property probe's directive from #8285 to #9703.** Add the `follow-through` label and the
  `<!-- soleur:followthrough script=scripts/followthroughs/inngest-luks-property-8296.sh earliest=... secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->`
  line to #9703's body in the same step that ends tracker 8285. The probe never exits 0 or 1, so it cannot close #9703.
  The comment on #9703 lists the deletion sites for whoever arms the feeder (probe, test, `run_suite` line, two
  `*.tsv` rows, the `test-affected-kb-consumers.baseline.txt` rows, the runbook 5a pointer).
- **D5. Ledger.** Remove the `hcloud_volume.inngest_redis` row; correct `hcloud_volume.inngest_redis_luks`
  (`does_not_defend` clause "until #8285 destroys it ... second copy", `live_verification` text "once it is enrolled
  on #8285") with dated past-tense wording; run `python3 scripts/lint-encryption-posture.py --repo-sweep`.
- **D6. Alert text unchanged.** Only comments in `betterstack-logs-alerts.tf` and `uptime-alerts.tf` change.
- **D7. Destruction record: fill, do not rewrite.** The PENDING-EVIDENCE cells are replaced by measured values;
  the `Superseded` markers and the addenda stay; a dated "Completion" section is appended that states the second
  corrected paragraph ("logical, guest-side, self-attested") and the new `dt` finding. `status` flips only after
  the CLO attestation.
- **D8. CLO attestation is a separate file at a named SHA**, `knowledge-base/legal/audits/2026-10-clo-attestation-8285-inngest-backstop-destruction.md`
  (naming follows `2026-09-07-clo-attestation-7786-off-host-log-claims.md`). Order: record content final in commit X;
  `soleur:legal:clo` audits at X; the attestation file cites X; a later commit Y flips `status: complete` and
  touches nothing else in the record. Both SHAs go in the PR body (a squash erases the order).
- **D9. ADR-142 gets a new dated addendum** stating the 2026-10-08 addendum is now landed (append-only: the old
  "Status: adopting" line is not edited). ADR-199 and the dedicated-single-host ADR keep their PR A addenda.
- **D10. #8316.** Fold in the two stale-comment fixes; comment with the PR link and the residual (suite-only
  `inngest_host_dark_gate`); retitle to that residual; keep open.
- **D11. Dispatch-side first, records last.** Commit order: evidence record fills (X) before any register edit, so the
  attestation sees the final numbers.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-142 via `soleur:architecture` with `## Addendum - 2026-10-<dd> (#8285, landed)`: the retirement is done
(volume 404 at 16:21:26Z; times from the evidence table); D1 to D4 of the 2026-10-08 addendum are realised except D4
(the provider-only fallback was never used); `op=luks-rollback` is retired on the dispatch side and the on-host arm is
inert (pointer to #9786); the live LUKS volume and `INNGEST_REDIS_LUKS_KEY` are the only copy and sole opener
(counsel review O4 now in force); the `dt` finding. Existing dated sections are not edited.

### C4 views

Read all three of `model.c4`, `views.c4`, `spec.c4` before concluding. Enumerated against the change: external human
actors (none added or removed); external systems and vendors (Hetzner block storage is not modelled as its own
element; Better Stack and Doppler edges unchanged); containers (`platform.infra.inngestRedis`: description only);
actor-to-surface access relationships (none change); derived cardinalities in edge prose (no count moves, confirmed by
`bash plugins/soleur/test/c4-count-parity.test.sh`). Edit: rewrite the `inngestRedis` description in `model.c4` to
remove "RETAINED PLAINTEXT BACKSTOP ... stays attached and intact ... op=luks-rollback ... retired under #8285", state
the retirement in the past tense, and drop "once enrolled on #8285" from the probe sentence. Regenerate with
`bash scripts/regenerate-c4-model.sh` (updates `model.likec4.json`); run `apps/web-platform/test/c4-code-syntax.test.ts`
and `c4-render.test.ts`.

### Sequencing

The ADR is authored in this PR, after the 404 read-back, describing a state that already exists.

## Infrastructure (IaC)

### Terraform changes

Deletions only: `inngest-backstop-wipe.tf` and `cloud-init-inngest-backstop-wipe.yml`; four variables removed from
`variables.tf` (`inngest_backstop_wipe_enabled`, `inngest_backstop_volume_id`, `inngest_backstop_wipe_server_type`,
`inngest_backstop_wipe_nonce`). `var.betterstack_logs_token` (reused by the wipe host) stays. No provider, version or
sensitive-variable change. `local.inngest_retired_plaintext_volume_id = "106261946"` **stays**: it keeps the cloud-init
template's `user_data` byte-identical so `hcloud_server.inngest` is never force-replaced (#9786 removes it at the next
planned replace). Its comment is rewritten in the past tense.

### Apply path

Per-merge apply only (no production command). Precondition, read before ship: the pre-merge infra-validation plan JSON
for the web-platform root shows **zero** resource changes (the wipe server and attachment were destroyed by the wipe
dispatch's teardown, the volume and attachment orphans by `destroy`). Any non-empty plan is a stop, not a proceed.

### Distinctness / drift safeguards

`inngest-host.test.sh` D1 scans stay (re-declaration of `hcloud_volume.inngest_redis` or a live reference to it still
reds). The scheduled drift detector (06:00 and 18:00 UTC) is the continuous check; the 18:00Z run on 2026-10-09 and
every later one must be clean. State storage unchanged (R2 backend).

### Vendor-tier reality check

No vendor tier gate involved. Cost falls by about USD 0.62 per month (the backstop volume line).

## Implementation Phases

Ordering rule: run the closing census (Phase 0) before any deletion; run each repo-global ratchet before the first
commit that touches a file it baselines (learning 2026-10-09); keep dated records append-only.

### Phase 0: re-pull evidence and census (read-only)

- 0.1 Re-read Hetzner (404 for the volume; server volumes; no wipe-labelled server; snapshots and backups for
  server 169426216 and any image of the volume: expected 0/0), Doppler `soleur-inngest/prd`
  `INNGEST_LUKS_ACTIVE_VOLUME_ID` / `INNGEST_LUKS_CUTOVER`, the newest `host_role=dedicated` probe row, the alert
  (`paused=false`), the first post-destroy scheduled drift run, `gh issue view 8285` / `6894` (still OPEN).
  Command shapes: `doppler run -p soleur -c prd_terraform --silent -- bash scripts/betterstack-query.sh ...` and the
  `HCLOUD_TOKEN_READONLY` Bearer for `GET /v1/...` (print status codes and non-secret fields only).
- 0.2 Re-run the `dt` measurement: `SELECT dt, ingest_time, JSONExtractString(raw,'message') AS m FROM remote($BS_TABLE) WHERE raw LIKE '%SOLEUR_INNGEST_BACKSTOP_WIPE%' ORDER BY dt FORMAT JSONEachRow`
  (hot window; the archive arm lacked `ingest_time` when probed). If the rows have aged out, use the Research Insights
  values and say so in the record.
- 0.3 Census by identifier over executable code and live docs (exclude `knowledge-base/project/**` history and
  `archive/`): `106261946`, `inngest_redis` not followed by `_`, `inngest-redis-store` (careful: the LUKS name contains
  it), `inngest-backstop`, `BACKSTOP_WIPE`, `RETIRE-INNGEST-BACKSTOP`, `role=inngest-backstop-wipe`,
  `INNGEST_LUKS_CUTOVER=rollback`, `luks-rollback`, `rollback-no-backstop`, `_g4_retire_read`. Record a disposition
  (delete / edit / keep-as-fixture) per hit in the PR checklist. Known keep-as-fixture sites: `inngest-redis-luks-loopback.test.sh`,
  `inngest.test.sh`, `scripts/inngest-host-state.test.sh`, `apps/web-platform/test/infra/inngest-luks-wrong-volume-alert.test.sh`
  (synthetic ids), the D1 scans in `inngest-host.test.sh`.
- 0.4 Run the baselined-file lints before editing: `python3 scripts/lint-shell-trace-credential-refusal.py --changed`
  and its D/E variants; `scripts/lint-infra-no-human-steps.py`; the grep-q-pipe guard; fixture-relative and
  fixture-dir-operand baselines; `scripts/test-affected-kb-consumers` baseline. Note current numbers (Rule E baseline
  for `apply-web-platform-infra.yml` is 5).
- 0.5 Record the pre-change sizes: `wc -c .github/workflows/apply-web-platform-infra.yml` (489,495) and the
  guard-vacuity `n_fires` against `MIN_FIRING_SUITES=51`.

### Phase 1: delete the wipe apparatus

Write-order inside the phase: ratchet/test edits that make deletions legal come in the same commit as the deletions
(a half state reds the suites that were green).

- 1.1 `git rm` `apps/web-platform/infra/inngest-backstop-wipe.tf`, `cloud-init-inngest-backstop-wipe.yml`,
  `inngest-backstop-wipe.test.sh`, `tests/scripts/lib/inngest-backstop-retire-gate.sh`,
  `tests/scripts/test-inngest-backstop-retire-gate.sh` (about 3,900 lines).
- 1.2 `.github/workflows/apply-web-platform-infra.yml`: delete the `inngest_backstop_retire` job (comment block through
  the last step, roughly lines 2084-2490), the `inngest-backstop-retire` enum option and its comment, the five inputs
  (`expected_inngest_volume_id`, `phase`, `wipe_run_id`, `erasure`, `clo_attestation_ref`) with their comment,
  and every prose mention in the `apply_target` and `confirm` descriptions and header comments. Revert PR A's
  "never untargeted while ... retire window" qualifier at the four sites: `apply-web-platform-infra.yml` (the
  `luks_key_touched` text and the line near 810), `apply-deploy-pipeline-fix.yml` (the ROUTING text),
  `scheduled-terraform-drift.yml` (the "run terraform apply locally" text). Find them with the anchor
  `retire window` / `NEVER untargeted` and compare with `git show d7dee46bb0` for the prior wording.
  Check `inputs.phase` has no other consumer first.
- 1.3 `variables.tf`: delete the four `inngest_backstop_*` variables and rewrite the neighbouring comment that names the
  dispatch (lines near 838 and 893-926 on today's tree) in the past tense.
- 1.4 Test registry and ratchets, in this order:
  - `scripts/test-all.sh`: delete the `run_suite "tests/scripts/inngest-backstop-retire-gate"` line and its comment block.
  - `scripts/suite-durations.tsv` and `scripts/suite-shard-legs.tsv`: delete the `tests/scripts/inngest-backstop-retire-gate`
    rows; run the shard-coverage suite to see whether leg balance needs regeneration.
  - `scripts/guard-vacuity-floor.test.sh`: remove `apps/web-platform/infra/inngest-backstop-wipe.test.sh` from
    `PROMOTED_FILES` and the PR A comment paragraph about it; add an itemised "-1 (#8285 PR B)" note to
    `MIN_FIRING_SUITES` **only if** the measured `n_fires` falls below 51 (ratchets are shrink-only; derive the number by
    running the suite, do not carry a literal).
  - `scripts/lib/inngest-probe-row.test.sh`: delete the ALLOW entry for the gate lib.
  - `scripts/lint-shell-trace-credential-refusal-e.baseline.txt`: set `apply-web-platform-infra.yml` to the measured
    count after the job is gone (comparison is by equality and shrink-only).
  - `plugins/soleur/test/terraform-target-parity.test.ts`: remove `inngest_backstop_retire` from `stripDispatchJobs`
    (about line 1204), the wipe-address set (about 1464-1470), the whole "inngest-backstop-retire dispatch" describe block
    (about 3480-3690), the loop entry near 6394, and fix comments (3736); replace with Guard 1's negative describe.
  - `plugins/soleur/test/web-host-escrow-preflight-census.test.ts`: drop `inngest_backstop_retire` from the three-job
    list and the `notCreator` loop (it must still contain three existing jobs, or the row is vacuous).
  - `plugins/soleur/test/stock-preflight-coverage.test.ts`: run; expect no change (PR A already removed the recut entry).
  - `apps/web-platform/infra/inngest-redis-luks.test.sh`: remove the `ACT="$(dget INNGEST_LUKS_ACTIVE_VOLUME_ID)"`
    classification arm, `_g4_retire_read` and the G4.b2 row; re-derive that suite's floor by measurement, itemised.
  - `tests/scripts/test-infra-privileged-tier-census.sh`: drop the two `INTENDED_DESTROYS` entries.
  - `tests/scripts/lib/inngest-host-{shape,replace,dark}-gate.sh`, `tests/scripts/lib/gate-suite-harness.sh`,
    `test-inngest-host-dark-gate.sh`, `inngest-userdata-budget.sh`: comments only (the orphans no longer exist; "until the
    retire dispatch destroys them" becomes past tense). Gate logic and counters stay.
  - `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md`: delete the `::inngest_backstop_retire` row.
    `apply-web-platform-infra-job-rationale.md`: condense the `§inngest_volume_recut` section to a short retired note (the
    workflow file's header cites it).
- 1.5 `inngest-arm-write-token.tf`, `inngest-host.tf` (lines near 324-340 and 551-558), `inngest-redis-luks.tf`
  (lines near 11-16, 62, 92, 122-127, 140-148), `betterstack-logs-alerts.tf` (the "DELIBERATELY DOES NOT DETECT"
  paragraph and the lines near 272-276), `uptime-alerts.tf` (near 517), `inngest-server-probe-heartbeat.test.sh` (header):
  comments only, past tense. No attribute, query or `incident_cause` changes.

### Phase 2: retire `op=luks-rollback`

- 2.1 `.github/workflows/cutover-inngest.yml`: remove the header line, the `luks-rollback` choice, and the `luks-rollback`
  disjunct in both ternaries (`environment:` and `DOPPLER_TOKEN_INNGEST_ARM`); fix the G3.7 comment that cites #7695.
- 2.2 `scripts/cutover-inngest.sh`: change the arm label `luks-cutover|luks-rollback)` to `luks-cutover)`; delete the
  `luks-rollback` G1 branch, the `absent:luks-rollback` G2 arm, the `LK_WANT=rollback` line, the rollback-only `NEXT`
  and `::warning::` lines; reword the `luks-cutover` G1 `done` refusal that says "dispatch op=luks-rollback"; fix the
  header comment near line 3412. `rolled-back` handling in `confirm_luks_state` stays (the FSM still reports it).
  Run the credential `--changed` lints on this file first (baselined-file rule).
- 2.3 `apps/web-platform/infra/cutover-inngest-workflow.test.sh` (about lines 4343-4420): update the block to `luks-cutover`
  only; delete the `LK_G1RB_ABORTED` row and the `absent:luks-rollback` clause; flip the choice-list/ENV_OPS rows to assert
  `luks-rollback` is **absent** (Guard 1); lower `_EXACT_FLOOR` (1069 today) to the measured dispatched count with an
  itemised comment line in the file's existing ledger style.
- 2.4 `scripts/followthroughs/inngest-luks-property-8296.test.sh`: delete the "rollback NEXT placement (AC-32)" block
  (the `placement_check` function, the NEXT-anchor row, the dead-wrapper rows, the label-missing/doubled rows, rows
  10 and its `move_next`/`row10` helpers); keep the 5a-heading assertion; lower `MIN_PASSES` (122) to the measured
  count with an itemised comment. Do not edit the probe script (its messages still point at 5a, which stays).
- 2.4b Deleted-assertion ledger (Sharp Edge: name the mutation each deleted row killed and what kills it now), kept in
  the PR checklist: `LK_G1RB_ABORTED` killed "rollback G1 stops admitting `aborted`" (verb gone; Guard 1 kills its return);
  `absent:luks-rollback` clause killed "rollback G2 loses the absent-pointer refusal" (same); probe-test AC-32 rows killed
  "the rollback NEXT line moves, is wrapped dead, or loses its anchors" (line gone); `inngest-redis-luks.test.sh` G4.b2
  killed "a second pointer reader appears in the retire job" (job gone; G4.g2 still fails any dispatch-side pointer write);
  the parity describe killed "the retire job loses its environment, concurrency group or id-pin ordering" (job gone;
  Guard 1 kills its return). Any row whose mutation still has a live target is kept, not deleted.
- 2.5 Runbook `inngest-luks-cutover-6894.md`: rewrite §5a under a heading that still matches `^## 5a\. .*op=luks-rollback`
  (for example "5a. `op=luks-rollback` is retired: what to do instead"). Content: the verb and the plaintext volume no longer
  exist; the live LUKS volume is the only copy; the signals that mean "store off the mapper" (wrong-volume alert,
  probe `rollback_inversion`) are now incidents, not rollbacks; recovery routes that exist (host replace
  `inngest-host-replace`, with #7228 strand note; key in Doppler `soleur-inngest/prd`); the ledger/register revert recipe is
  removed because there is no plaintext volume to revert to. Update §1-§6 mentions, §5b (turn into a past-tense record
  of the retirement, keep the triage tables since they document what was done), the "Related" list, and
  `inngest-server.md`. Run `lint-infra-no-human-steps.py` on every touched runbook.
- 2.6 Comment on #9786: the dead on-host `rollback)` arm in `inngest-luks-cutover.sh`, its FSM comments and fixtures
  join the next-replace removal list.

### Phase 3: ledger

- 3.1 Remove the `hcloud_volume.inngest_redis` row from `scripts/encryption-posture-ledger.json`.
- 3.2 Correct `hcloud_volume.inngest_redis_luks`: `does_not_defend` loses the backstop sentence and gains one dated
  clause ("the plaintext copy was destroyed 2026-10-09; erasure is logical, guest-side and self-attested"); `live_verification`
  drops "once it is enrolled on #8285". No `mechanism` change.
- 3.3 `python3 scripts/lint-encryption-posture.py --repo-sweep` must print `0 failing checks -> PASS`; also
  `bash scripts/lint-encryption-posture.test.sh` (its fixture mentions the address and must not read the live ledger).

### Phase 4: probe, stale prose, comments

- 4.1 Keep `scripts/followthroughs/inngest-luks-property-8296.{sh,test.sh}` and the `run_suite` line. Pre-deletion
  note (task 3.4a) recorded in the PR checklist: the probe's daily comment never carried a days-to-expiry line.
- 4.2 `scripts/followthroughs/inngest-luks-cutover-6894.sh`: change the final `NEXT` echo (it still says to destroy the
  backstop by 2026-10-22) to past tense; leave the RETIRED header. Run the fixture-relative baseline first.

### Phase 5: records (counts and identifiers only; no payload, no key material, no token value)

- 5.1 Destruction record `knowledge-base/legal/audits/inngest-aof-backstop-destruction-record.md`: replace every
  `PENDING-EVIDENCE` from the Research Insights table (re-pulled in Phase 0), including the three per-phase process rows
  (`headSha` 32b2fe2abb for all three runs; `git diff --quiet` of the apparatus paths between the reviewed commit
  `50fd47bb8a` and the dispatch head, fetched via `refs/pull/9784/head`, with the exit status; go-ahead quotes supplied by
  the parent session, never invented: if unavailable write "recorded in the pipeline session; quote not in the repo");
  state the Terraform 1.10.5 note, the destroy apply-completion time (16:21:24Z delete action; apply step end from the
  run) and the first-404 time (16:21:26Z); the variant used is `evidence-path` (D4 not used); append a dated Completion
  section with the second corrected paragraph and the `dt` measurement ("`dt` is the sender's clock; `ingest_time` is
  receipt; the window check holds on `ingest_time`"). Keep the template's own Superseded markers. No claim of physical or
  secure erasure anywhere.
- 5.2 Article 30 register (`knowledge-base/legal/article-30-register.md`): append a dated bracket to PA-13 (e), PA-21 (f)
  and PA-22 (f) next to the `2026-09-21 AMENDMENT (#8296)` text: backstop destroyed; the sentence "logical, guest-side,
  self-attested"; first-404 16:21:26Z and destroy completion 16:21:24Z (delete action) / apply-completion from the run;
  nothing deleted from the cells. Never `docs/legal/**`.
- 5.3 `knowledge-base/legal/compliance-posture.md`: add a Completed Compliance Work row (model: the #8734 deletion row),
  same sentence and times; bump `last_updated` (the file's rule).
- 5.4 ADR-142 addendum (see Architecture Decision); `model.c4` + regenerate.
- 5.5 `knowledge-base/operations/expenses.md`: mark the `Hetzner Volume (inngest, 10 GB)` row retired 2026-10-09 (precedent: the
  CX23 hermes-agent row) and past-tense the concurrent-billing sentence on the LUKS row; the throwaway cpx22 ran minutes
  (sub-cent) and gets a one-clause note. Delegate to `soleur:operations:ops-advisor` or edit by the same shape.
- 5.6 `knowledge-base/product/roadmap.md` L31: status to Done with the PR number.
- 5.7 Older template `inngest-aof-destruction-record.md`: keep the `Superseded` banner (2026-09-21), no completion (task 3.7).
- 5.8 Learning file for the session (the `dt` measurement is already a learning; add only what is new, for example the
  probe-directive/tracker-lifetime coupling).
- 5.9 CLO attestation per D8: commit X (record final), invoke `soleur:legal:clo` at X, write the attestation file, then
  commit Y flipping `status: complete`.

### Phase 6: verify locally (CI is the authority; the box is contended)

Run the file-selected set, then the repo-global ones by name:

- `bun test plugins/soleur/test/terraform-target-parity.test.ts plugins/soleur/test/web-host-escrow-preflight-census.test.ts plugins/soleur/test/stock-preflight-coverage.test.ts plugins/soleur/test/workflow-file-size.test.ts`
- `bash apps/web-platform/infra/{cutover-inngest-workflow,inngest-host,inngest-redis-luks,inngest-luks-cutover,inngest-server-probe-heartbeat}.test.sh`
- `bash scripts/followthroughs/inngest-luks-property-8296.test.sh`; `bash scripts/lib/inngest-probe-row.test.sh`
- `bash tests/scripts/test-inngest-host-{shape,replace,dark}-gate.sh tests/scripts/test-infra-privileged-tier-census.sh`
- `bash scripts/guard-vacuity-floor.test.sh`; the shard coverage suite; the Rule E / D / base credential lints (`--changed`);
  `scripts/lint-infra-no-human-steps.py`; grep-q-pipe guard; fixture baselines; `python3 scripts/lint-guard-contract.py`
- `python3 scripts/lint-encryption-posture.py --repo-sweep`; `bash plugins/soleur/test/c4-count-parity.test.sh`;
  `bash scripts/regenerate-c4-model.sh` then the two C4 tests
- A YAML parse and actionlint pass over both edited workflows; `wc -c` on `apply-web-platform-infra.yml` (must be well under 490,000).
- Rollback rehearsal in a scratch detached worktree: `git revert --no-commit` the branch commits, run the suites the
  revert PR would need (expected: green except the ledger/lint, see Rollback), discard.

### Phase 7: review and ship

`soleur:review`, `soleur:qa`, `soleur:compound`, then `soleur:ship` (Phase 5.5 CLO gate applies to the record). PR body first
line: "Merging this alone does not hand-write to production: it triggers the routine per-merge apply (no changes expected) and
the container release." Body uses `Ref #8285` / `Ref #6894`; cite both attestation SHAs; squash message carries no closing
keyword. The merge queue is on; wait for the queue, not for a manual merge.

### Phase 8: post-merge (from a detached `origin/main` worktree)

1. Per-merge apply run for the merge commit concluded success with zero changes; the container release job state recorded
   (the previous deploy failed on the unrelated `sandbox_broken` canary: if it recurs, link its own tracker, do not attribute).
2. From the detached worktree: ledger lint PASS; `git grep -n "inngest-backstop-retire\|luks-rollback"` over live code returns only
   the Guard 1 assertions and dated history; `gh workflow view apply-web-platform-infra.yml` shows no retire option.
3. Hetzner: volume 404, server volumes `[106903269]`; Better Stack: newest dedicated probe row on 106903269; alert `paused=false`;
   18:00Z-or-later drift run green.
4. Edit #9703's body per D4 (label + directive) and post the deletion-site list; comment on #9786 and #8316 (D10).
5. `gh issue close 8285` and `gh issue close 6894`, each with a comment: PR link, the three run URLs
   (https://github.com/jikig-ai/soleur/actions/runs/37950928039, .../37955244979, .../37958051426) and the 404 read-back
   (`GET /v1/volumes/106261946 -> 404 at 2026-10-09T16:21:26Z`, re-read at post-merge time). Add a dated note that #8285's
   Follow-through paragraph ("the destroy PR also deletes the probe") is superseded by D4.

## Files to Delete

| Path | Lines |
|---|---|
| `apps/web-platform/infra/inngest-backstop-wipe.tf` | 89 |
| `apps/web-platform/infra/cloud-init-inngest-backstop-wipe.yml` | 276 |
| `apps/web-platform/infra/inngest-backstop-wipe.test.sh` | 1075 |
| `tests/scripts/lib/inngest-backstop-retire-gate.sh` | 530 |
| `tests/scripts/test-inngest-backstop-retire-gate.sh` | 1955 |

## Files to Edit

| Path | Change |
|---|---|
| `.github/workflows/apply-web-platform-infra.yml` | delete job, option, five inputs, prose; revert qualifier (net byte decrease) |
| `.github/workflows/apply-deploy-pipeline-fix.yml`, `scheduled-terraform-drift.yml` | revert the retire-window qualifier |
| `.github/workflows/cutover-inngest.yml` | retire `luks-rollback` (header, choice, two ternaries), G3.7 comment |
| `scripts/cutover-inngest.sh` | arm label, rollback branches, NEXT/warning lines, stale comment |
| `apps/web-platform/infra/variables.tf` | four variables + comments |
| `apps/web-platform/infra/{inngest-host,inngest-redis-luks,inngest-arm-write-token,betterstack-logs-alerts,uptime-alerts}.tf`, `inngest-userdata-budget.sh` | comments only |
| `apps/web-platform/infra/{cutover-inngest-workflow,inngest-redis-luks,inngest-server-probe-heartbeat,inngest-luks-cutover}.test.sh`, `inngest-host.test.sh` | rows, floors, comments (see Phases 1-2) |
| `plugins/soleur/test/{terraform-target-parity.test.ts,web-host-escrow-preflight-census.test.ts}` | remove retire coverage, add Guard 1 |
| `scripts/{test-all.sh,suite-durations.tsv,suite-shard-legs.tsv,guard-vacuity-floor.test.sh,lint-shell-trace-credential-refusal-e.baseline.txt}`, `scripts/lib/inngest-probe-row.test.sh` | registry and ratchets |
| `tests/scripts/{test-infra-privileged-tier-census.sh,test-inngest-host-dark-gate.sh}`, `tests/scripts/lib/{inngest-host-shape-gate,inngest-host-replace-gate,inngest-host-dark-gate,gate-suite-harness}.sh` | entries/comments |
| `scripts/followthroughs/inngest-luks-property-8296.test.sh`, `scripts/followthroughs/inngest-luks-cutover-6894.sh` | AC-32 block and floor; one echo |
| `scripts/encryption-posture-ledger.json` | remove row, correct LUKS row |
| `knowledge-base/legal/audits/inngest-aof-backstop-destruction-record.md`, `knowledge-base/legal/article-30-register.md`, `knowledge-base/legal/compliance-posture.md` | records |
| `knowledge-base/engineering/architecture/decisions/ADR-142-*.md`, `diagrams/model.c4`, `diagrams/model.likec4.json` (generated) | landed addendum; C4 |
| `knowledge-base/engineering/operations/runbooks/{inngest-luks-cutover-6894,inngest-server,infra-credential-tiers-8209,apply-web-platform-infra-job-rationale,betterstack-log-query}.md` | runbook convergence |
| `knowledge-base/operations/expenses.md`, `knowledge-base/product/roadmap.md` | ledger and roadmap row |

## Files to Create

- `knowledge-base/legal/audits/2026-10-clo-attestation-8285-inngest-backstop-destruction.md` (D8)
- `knowledge-base/project/specs/feat-one-shot-8285-6894-pr-b-retire-wipe-apparatus/{tasks.md,decision-challenges.md,deferral-sole-copy-protection-issue-body.md}` (the last backs #9879, already filed)
- A learning under `knowledge-base/project/learnings/` only if the session finds something new (Phase 5.8)

## Acceptance Criteria

### Pre-merge (PR)

1. The five files in "Files to Delete" are gone; `git grep -n -E "inngest_backstop|inngest-backstop-(wipe|retire)|BACKSTOP_WIPE|RETIRE-INNGEST-BACKSTOP"` over `.github scripts tests apps plugins` returns only Guard 1 assertions and clearly dated history comments (the sweep excludes `knowledge-base/project/plans` and `knowledge-base/project/specs`, which quote the phrases by design).
2. `apply-web-platform-infra.yml` has no `inngest-backstop-retire` option, no `inngest_backstop_retire` job, none of the five inputs; `wc -c` is lower than the pre-change 489,495 and `workflow-file-size.test.ts` passes.
3. `cutover-inngest.yml` and `scripts/cutover-inngest.sh` contain no `luks-rollback`; `luks-cutover` still works (its suite rows pass).
4. `scripts/encryption-posture-ledger.json` has no `hcloud_volume.inngest_redis` row; the LUKS row text is corrected; `python3 scripts/lint-encryption-posture.py --repo-sweep` prints `0 failing checks -> PASS`.
5. The infra-validation plan JSON for the web-platform root shows zero resource changes.
6. The destruction record has zero `PENDING-EVIDENCE`, states "logical, guest-side, self-attested" and no physical-erasure claim, records the `dt` measurement, lists attestation SHA X and flip SHA Y, and `status: complete` exists only at Y.
7. Article 30 PA-13 (e), PA-21 (f), PA-22 (f) and the compliance-posture row carry the sentence and both times; no existing text was deleted from any cell.
8. `model.c4` and `model.likec4.json` regenerate cleanly; C4 syntax, render and count-parity tests pass.
9. Every floor and baseline moved by the measured amount with an itemised note: `_EXACT_FLOOR`, probe-test `MIN_PASSES`, `inngest-redis-luks.test.sh` floor, `MIN_FIRING_SUITES` (only if needed), Rule E baseline, `*.tsv` rows. `bash scripts/guard-vacuity-floor.test.sh` passes.
10. Guard 1 (below) is green and its mutation rows were each seen RED before the guard was finalised.
11. PR title, body and every commit message contain `Ref #8285` / `Ref #6894` and no closing keyword; PR body first line is the production statement in Phase 7.
12. The pre-merge Hetzner re-read at ship time is 404 and is recorded in the PR body.

### Post-merge

13. Phase 8 steps 1 to 5 all hold; both trackers are closed with the three run URLs and the 404 read-back; #9703 carries the directive and label; #8316 and #9786 carry their comments.
14. The next two scheduled drift runs after the merge report no drift.

## Guard Contract

### Guard 1 — a retired dispatch stays retired

**Property.** No workflow surface can dispatch the retired backstop apparatus or the retired `luks-rollback` verb: no enum option, job, input, `-var inngest_backstop_*` flag or Terraform address for the wipe host in `apply-web-platform-infra.yml`, and no `luks-rollback` in `cutover-inngest.yml`'s choice list, either ternary, or `scripts/cutover-inngest.sh`'s case labels.

**Assembly.** `apply-web-platform-infra.yml`: the `on.workflow_dispatch.inputs.apply_target.options` list, the `jobs` key set, the `inputs` key set, and every non-comment line (so a `-target=hcloud_server.inngest_backstop_wipe` hidden in another job's step also reds). `cutover-inngest.yml`: `on.workflow_dispatch.inputs.op.options`, the `environment:` expression and the `DOPPLER_TOKEN_INNGEST_ARM` expression. `scripts/cutover-inngest.sh`: every case label and every non-comment line. Chokepoint: parsed YAML for the three structured surfaces (`yq`/Python in the shell suite, `yaml` in the TS test) plus a comment-stripped line sweep for the literals; members are not listed by shape, so a fourth surface added later is caught by the line sweep. Homes: a negative `describe` in `terraform-target-parity.test.ts` and the rewritten block in `cutover-inngest-workflow.test.sh`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Re-add `inngest-backstop-retire` to the `apply_target` options list | RED |
| 2 | Re-add a job keyed `inngest_backstop_retire` with `if: false` | RED (job key set, not just the `if:` text) |
| 3 | Re-add `luks-rollback` to the `op` choice list only (both ternaries untouched) | RED |
| 4 | With every surface compliant, add `-var inngest_backstop_wipe_enabled=true` inside an unrelated job's step | RED (second member after a compliant first; the line sweep covers every job) |
| 5 | Re-add the `luks-cutover\|luks-rollback)` case label in the orchestrator | RED |
| 6 | Point the suite's workflow path at an empty temp file (guard's own dispatch) | RED (non-vacuity floor: the sweep must have inspected at least the known option count) |

**Harness rows.** Suite edit that must go RED: delete the list of retired literals from the suite, leaving the loop to iterate zero items (the floor row must fail). Must-PASS non-canonical inputs: a workflow whose only mention of `inngest-backstop-retire` is in a `#` comment, and a workflow that keeps `luks-cutover` (the real surviving op) in the same list as the removed one.

**Anchor.** No stored value is compared: the property is absence, read off the live file. A weakening must edit the guard itself (visible in review) or the live file (then the sweep reds). The merge-base copy of the suite is not consulted.

## Test Scenarios

1. Dispatching a removed `apply_target` value is refused by GitHub (dispatch validation), not by a job.
2. `op=luks-cutover` on the live host still refuses at G1 (flag `done`) and G2 (pointer set), with the reworded text.
3. `inngest_host_shape_gate` / `inngest_host_replace_gate` still abort on any action against the retired addresses (logic unchanged, suites green).
4. The probe test still passes on a ledger with no backstop row (its `BACKSTOP_N=0` path) and still asserts the 5a heading.
5. A fixture ledger containing a `hcloud_volume.inngest_redis` row with no matching resource now fails the lint (existing behaviour; confirm it stays).

## User-Brand Impact

**If this lands broken, the user experiences:** nothing visible in the web app. The failure modes are operational: a deleted guard that
was still load-bearing could let a later change act on the live LUKS volume (the only copy of armed reminders and queued
work), and a wrong "logical erasure" sentence in a register is a compliance misstatement about their data.

**If this leaks, the user's data is exposed via:** no new vector: the PR adds counts and identifiers only (volume id, run ids,
times, a filesystem UUID); no payload, key, token or hostname beyond what PR A already published. The one residual exposure is the
already-recorded self-attested nature of the erasure, which the records state rather than hide.

**Brand-survival threshold:** single-user incident (carried from PR A: the retired object held a plaintext copy of in-flight
user prompts and agent output, and the record is the only proof the copy ended). CPO sign-off carried from PR A's plan.
`soleur:engineering:review:user-impact-reviewer` runs at review time.

## Domain Review

**Domains relevant:** Engineering, Legal, Operations (expenses), Product (sign-off only)

### Engineering (CTO)
**Status:** carried forward from PR A's plan (same decision; no new approach). **Assessment:** deletion order and ratchet handling per Phase 0 and 1; baked on-host arm untouched (D3); no host replace.

### Legal (CLO)
**Status:** carried forward; attestation of the completed record at a named SHA is a Phase 5 deliverable (D8). **Assessment:** wording stays "logical, guest-side, self-attested"; D4 provider-only wording not used; Article 30 cells amended by dated append only.

### Operations (COO)
**Status:** reviewed inline. **Assessment:** expenses row retired 2026-10-09; roadmap L31 to Done; no new vendor or account.

### Product/UX Gate
**Tier:** none (no user-facing surface). **Decision:** auto-accepted (pipeline). **Agents invoked:** none (CPO sign-off carried).
**Skipped specialists:** none. **Pencil available:** N/A (no UI surface).

## Observability

```yaml
liveness_signal:
  what: hourly SOLEUR_INNGEST_SERVER_PROBE row from host_role=dedicated, watched by logtail_exploration_alert.inngest_luks_wrong_volume (armed, paused=false); the dead-probe heartbeat betteruptime_heartbeat.inngest_server_probe is declared but unarmed until #9703
  cadence: hourly probe; alert check_period 300 s
  alert_target: Better Stack incident email
  configured_in: apps/web-platform/infra/betterstack-logs-alerts.tf; apps/web-platform/infra/uptime-alerts.tf
error_reporting:
  destination: GitHub Actions logs for the per-merge apply and the release (layer 6); Better Stack Logs for the probe (layer 3)
  fail_loud: a non-empty per-merge plan or a red drift run fails the workflow; the property probe (re-homed to #9703) comments ACTION REQUIRED on disagreement
failure_modes:
  - mode: a leftover reference to a deleted file or job breaks a suite or the dispatch form
    detection: the file-selected suites, the repo-global ratchets and the workflow parse in Phase 6, then CI
    alert_route: red PR checks
  - mode: the per-merge apply plans a change against the live Inngest host or the LUKS pair
    detection: infra-validation plan JSON read before ship; apply job destroy-guard
    alert_route: failed workflow run, stop before ready
  - mode: the store moves off the LUKS mapper after the rollback verb is gone
    detection: wrong-volume alert and the probe rollback_inversion verdict
    alert_route: Better Stack email; runbook section 5a (rewritten) says it is an incident, not a rollback
  - mode: the probe pipeline goes silent while the heartbeat is unarmed
    detection: the re-homed property probe reports CANNOT ESTABLISH daily on #9703
    alert_route: issue comment on #9703
logs:
  where: GitHub Actions run logs; Better Stack source 2457081
  retention: Actions log retention; Better Stack hot window plus archive (the evidence rows are copied into the record for that reason)
discoverability_test:
  command: jq -e '[.stores[].store] | index("hcloud_volume.inngest_redis") == null' scripts/encryption-posture-ledger.json
  expected_output: true
```

The live read-backs (Hetzner 404, probe row, alert state) need credentials and are post-merge acceptance criteria (13), not this
test; the test above is the credential-free, sub-second proof that the ledger no longer carries the retired row.

## Risks and Sharp Edges

- **Ratchet order.** A deletion that is legal only together with a floor/baseline change must be committed with it. Floors are
  measured, never summed from memory, and each carries an itemised note.
- **Workflow size.** The file has 505 bytes of headroom today: do not add text to it before the job is deleted.
- **Probe coupling.** Editing `cutover-inngest.sh` breaks the probe test's AC-32 block unless Phase 2.4 lands in the same commit.
- **Sole copy after this PR.** The LUKS volume 106903269 is the only copy of the store. PR B deletes two things that
  treated it as never-acted-on (the retire job and its gate); every remaining guard that names it stays
  (`inngest_host_shape_gate`, `inngest_host_replace_gate` named-live counters, the destroy-guard census, the live-store
  checks in `cutover-inngest.sh`). Operations that would make it unreachable and the guard that remains for each: volume
  destroy or replace (shape and replace gates: `luks_volume_touched`, destroy-guard); attachment replace (replace gate
  admits it on purpose for `inngest-host-replace`); state-forget (shape gate `forget_present`); key loss (none: the
  passphrase lives only in Doppler). Protection beyond that is #9879, not this PR.
- **Self-approval.** All three runs were dispatched and approved by the same login. The record states this plainly; it is a fact
  about the evidence, not a defect to hide.
- **Better Stack retention.** If Phase 0.2 finds the rows aged out, the plan-time values are the only copy: use them and say where they came from.
- **Merge triggers a release.** `apps/web-platform/infra/**` also matches the container release paths; a red canary on that
  release is not caused by this PR.
- **Plan lints.** A plan whose `## User-Brand Impact` is empty or holds only filler fails deepen-plan; this one is filled. The Guard
  Contract mutation matrix is a table (the lint counts rows, not list items).
- **Prose lint.** Runbook edits describe automation, not human-run infra steps; run `lint-infra-no-human-steps.py` before commit.

## Rollback

Code and docs are revertable with `git revert` of the squash commit, with these exceptions: (1) do not restore the ledger row
(the volume no longer exists; the restored row would fail the lint's resource resolution or expire 2026-10-22); a partial
revert keeps `scripts/encryption-posture-ledger.json` and the records as merged. (2) Reverting restores the retire job against
a volume that is gone; its Convergence read would report the post-condition already holds, but treat the restored job as inert
and delete it again. (3) No production state is changed by this PR, so nothing needs undoing there. Execute the revert once in a
scratch detached worktree before merge (Phase 6), record the suites that go red, and put the resulting recipe in the
runbook §5b past-tense record (the artifact that outlives this plan), not here.
