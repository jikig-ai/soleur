# Runbook — the web-2 LUKS rebirth (#9372, single-use)

**Status:** the workflow is merged and **inert** until dispatched; nothing here has been run. Written 2026-10-05 (ADR-263 addendum).
**Applies to:** the live `web-2` standby only. `web-1` is refused by name at every layer.

web-2 holds no user data and takes no traffic (weight 0, no soak marker). Its volume was created ext4, so the guest-side
provisioner refuses to format it. This workflow deletes that **empty** volume through the Hetzner API, forgets it from
Terraform state, and replaces the server so a raw volume is created and formatted LUKS at first boot. Every dispatch needs
the owner's explicit go-ahead for that specific dispatch; the environment approval and the typed confirm are guards, not
the authorization. Do not dispatch from a menu answer or a "continue".

## Before the first dispatch

1. The **retirement change** is merged: it deletes `apply-web-escrow-create.yml` and flips the rotation HALT's `create`
   exemption in `tests/scripts/lib/destroy-guard-filter-web-platform.jq`. An apply dispatch refuses until it is (the
   `flip-precondition` step prints `NOT met`; a `plan_only` run prints `PENDING`).

   **Landed from the merge of the retirement change (PR #9569, #9372).** That change deletes the escrow-create workflow and makes the
   rotation HALT count a `create` of the web-class passphrase, so the flip precondition can read met. Verify it against the merged
   tree before the first dispatch (run it with `GITHUB_OUTPUT` unset); the output must contain `flip precondition: MET`:

   ```bash
   bash scripts/web2-rebirth.sh flip-precondition yes
   ```

2. Pause both push-apply workflows and confirm they are idle. Both were `active` (not paused) on 2026-10-06, and the merge of the
   retirement change fires a routine push-apply (no Terraform diff is expected). Order:

   1. Wait for the push-apply run on the merge SHA to finish green with a plan of "No changes". A different plan is a
      finding to read, not noise.
   2. Only then pause both:

      ```bash
      gh workflow disable apply-web-platform-infra.yml
      gh workflow disable apply-deploy-pipeline-fix.yml
      ```

   3. Check both, nothing may be queued or running, then dispatch:

      ```bash
      gh api repos/jikig-ai/soleur/actions/workflows/apply-web-platform-infra.yml --jq .state      # disabled_manually
      gh api repos/jikig-ai/soleur/actions/workflows/apply-deploy-pipeline-fix.yml --jq .state     # disabled_manually
      ```

   After the rebirth, re-enable them only once closing-checklist row 3 (the host-key pin re-capture) is done, with
   `gh workflow enable apply-web-platform-infra.yml` and `gh workflow enable apply-deploy-pipeline-fix.yml`. Neither this
   runbook nor the apply workflows document a catch-up for a diff merged while they were paused (a push-apply fires on a push
   that touches its path filters, and `workflow_dispatch` is its documented manual escape hatch for ad-hoc applies), so the
   owner decides how such a diff is applied.

3. `image_tag` is a published web-platform release that carries the fresh-boot provisioner: take the newest tag at or after the
   merge commit of the PR that added this workflow (`gh release list --limit 5`). Either `v3.1.2` or `3.1.2` is accepted. The
   coherence preflight proves the image's baked host-scripts hash equals `local.host_scripts_content_hash` at the dispatch commit.
4. The Hetzner token the run uses must be the write-capable one. A `403` on detach, DELETE or reboot (the error names it) means
   the credential loader exported the read-only token: stop and fix the loader's Tier-B secret before re-dispatching.
5. `bash scripts/web-host-escrow-preflight.sh` is green (the workflow runs it first, before any Terraform command or Hetzner call).

## Dispatch and watch

Plan first (the default; no write of any kind):

```bash
gh workflow run web2-luks-rebirth.yml --ref main \
  -f confirm=REBIRTH-web-2-LUKS -f expected_volume_id=106466179 -f image_tag=<vX.Y.Z> -f plan_only=true -f reason='<why>'
gh run list --workflow web2-luks-rebirth.yml --limit 1 --json databaseId,status,conclusion,url
gh run watch <databaseId> --exit-status          # confirm the run actually started: the shared concurrency group keeps one
                                                 # running and one pending run, and a queued run can displace an older pending one
```

A plan-only run is also held at the `web-platform-infra-apply` environment approval before any step runs, so `gh run watch` shows it
waiting until the owner approves.

Read the run log's `verdict:` line, the printed `pinned volume:` line, the emptiness verdict (it prints the minimum, maximum,
spread and ceiling) and the dispatch summary.

**Reading an emptiness RED.** `RED reason=used_bytes_absent_or_host_dark` means no row for the used series survived the query: a dark host, a changed
stored row shape, more than one distinct device reporting `/mnt/data` in the window, or a missing, empty or non-string `tags.device` on
some row (the one-device clause drops that metric's whole group, so the same fault on the total series reads `total_bytes_absent`).
The other reasons (`coverage_gap`, `stale`, `not_empty`, `not_flat`, `used_bytes_zero_or_missing`, `used_bytes_malformed`,
`total_bytes_malformed`, `not_the_20gb_volume`) name the FIRST rule that failed, in that order; `emptiness_body_unparseable` and
`emptiness_judge_error` mean the answer could not be read, and exit code 2 means the read did not answer at all (no verdict). To re-run the read-only
control without a dispatch: `doppler run -p soleur -c prd_terraform -- bash scripts/web2-rebirth-emptiness.sh` (prints `PASS ...` with
hours, newest age, min, max and spread, or the RED reason); to see which devices report, run the same WHERE with a
`GROUP BY JSONExtractString(raw,'tags','device')` through `scripts/betterstack-query.sh`. The control uses the Doppler read
credentials and the workflow uses the repo secrets `BETTERSTACK_QUERY_*`, so the first plan-only dispatch is the credential-parity check.

**The 1 GiB ceiling is a coarse bound, not proof of emptiness:** the owner reads the
printed used-bytes values from the plan-only run before authorizing the apply dispatch: the `web-platform-infra-apply` environment
approval is a job-level gate, so it comes BEFORE the evidence step, and an apply dispatch's PASS flows into the delete in the same
approved job. The Better Stack paths were confirmed 2026-10-06 and the observed level is about 16 MB (min 15.6 MB, max 16.0 MB over
169 h; the header of `scripts/web2-rebirth-emptiness.sh` carries the control). That is the volume's own reading, not an independent
empty reference: an ext4 volume is never byte-empty, and neither the 1 GiB ceiling nor the 64 MiB spread proves emptiness. In the `heal:detach_done` window the freshness bound is dropped and coverage falls to 24 h (a detached device stops reporting); the zero
floor, the ceiling, the spread and the size window still apply. Only after the owner approves **that** apply, dispatch with `-f plan_only=false` and approve the
`web-platform-infra-apply` environment gate. The classifier verdict is also a job output (`verdict`).

## The classifier: what each verdict means

Every dispatch starts by classifying Hetzner and Terraform state. The run writes nothing until the verdict is `proceed`, a
`heal:` window or `resume:post_apply`. A `refuse:` ends the run RED before any write. Every write step additionally requires its
proofs (the delete step refuses unless the emptiness, never-pooled and pre-plan proofs are present) and `plan_only` can never
reach a write.

| Verdict | What is true | What the run does |
|---|---|---|
| `proceed` | the pinned ext4 volume is attached to web-2 and held by state | full path |
| `heal:detach_done` | detached last time | continues at DELETE; the emptiness gate drops its freshness bound (a detached device stops reporting) |
| `heal:delete_done` | volume gone (404), state still holds it | continues at `state rm` |
| `heal:state_rm_done` | state is clean, the old server exists | continues at the `post` plan |
| `heal:apply_midway` | volume and server both gone | the `post` plan creates both |
| `heal:volume_created` | the raw volume exists in state, not attached | the `post-heal` plan |
| `resume:post_apply` | the rebirth already ran: the new volume is in state and is the ONLY volume web-2 holds, the pinned volume is gone and the server is younger than 72 h (the never-pooled step must also pass in the same run, or the run is RED before any write) | **nothing is replaced or deleted**: a resume plan (no `-replace`; it may only ADD what a partly failed apply left missing, e.g. the NIC, the attachment or the firewall update), then the readiness poll, the recovery check and the reboot |
| `refuse:already_reborn` | the same, but the server is older than 72 h or its age is unknown | **single use**: a second rebirth needs a new reviewed pin and PR |
| `refuse:state_does_not_hold_the_pinned_volume` | web-2 already holds the new volume but the pinned volume still exists | not a settled rebirth: stop and read the classifier line |
| `refuse:orphan_raw_volume` | a raw volume with the name exists and state does not hold it | not healed automatically (it could hold data). The owner confirms in Hetzner that it is raw and unattached, deletes it (a production write needing the owner's approval), then re-dispatches |
| `refuse:orphan_server` | Hetzner has a web-2 server that state does not hold | the post plan would try to create a second server of that name. The owner decides: import it into state or delete it (a production write), then re-dispatch |
| `refuse:web2_holds_another_volume` | web-2 has a volume other than the pin attached | the server replace would detach it; stop and read the classifier line |
| `refuse:pinned_volume_not_the_empty_plaintext_one` | the pin is not ext4, or its name/labels differ | stop; the premise is false |
| `refuse:inconsistent_pin_listing`, `refuse:pinned_volume_attached_elsewhere`, `refuse:duplicate_volume_name`, `refuse:state_*` | the world does not match the contract | stop and read the classifier line in the log |
| `refuse:push_apply_pause_not_real` | a push apply could re-create a plaintext volume | pause both workflows, wait for idle, re-dispatch |

A **failed boot is not healed here**: use `web_host_replace` for web-2 (it carries the new volume forward by design). After a
completed apply, a failed readiness poll, recovery check or reboot is resumed by re-dispatching with the same inputs
(`resume:post_apply`); the readiness reader looks back 4 days so the once-per-instance readiness row of a 72 h-old rebirth is still found, and the
never-pooled step runs on every verdict and the reboot refuses without its proof (with the soak marker present the run goes RED before any write and nothing is touched).
**There is no escrow retry.** An `escrow=missing` birth can only be redone by a second rebirth, which `refuse:already_reborn` blocks
once the server is older than 72 h and which needs a new reviewed pin in any case.

## What the run proves, and what it does not

Evidence before any write, all read without SSH: 7 days of Better Stack `host_metrics` used-bytes for `/mnt/data` (hour coverage,
freshness, a non-zero minimum because a missing value path reads as 0, the 1 GiB ceiling, a 64 MiB spread so a volume that took
writes is not "idle", and a 15 to 21.5 GB total so a mis-mounted root disk cannot pass), the soak marker absent by exact-name
membership over secret **names** (a list shape the reader cannot interpret is a refusal, never "absent"), the Hetzner volume still
ext4 with the pinned id, name and labels. **Not measured by this run:** web-2's serving weight (no weight orchestrator exists in the
repo at this SHA; the marker is the only seam and the dispatch is only from `main` where the anti-pooling CI suite `lb-weight-gate.test.sh` has run). The Better Stack JSON paths were confirmed on 2026-10-06 (`tags.host`, `namespace`, `tags.mountpoint`, `name`, `gauge.value`); the
`dm-*` exclusion in `vector.toml` (whether it drops the LUKS mapper device) is still **unconfirmed**; an absent field fails closed.

After the apply: a `SOLEUR_FRESH_BOOT_READY` row newer than web-2's own Hetzner creation time with `luks=1 luks_arm=formatted
escrow=ok`; a read-only birth-time consistency check of the escrowed header and the two passphrase copies (`restore NOT exercised;
open until #7992 and a restore drill`); then an hcloud reboot is **issued**. The run never claims the volume reopens: the proof is a
later luks-monitor probe row on a `boot_id` other than the readiness row's, `crypto_LUKS` on `/dev/mapper/workspaces`, graded by
`scripts/followthroughs/web2-luks-live-6931.sh` and required by the soak marker. Until then web-2 is *provisioned, proof pending*, at
weight 0, holding no workspace data. The dispatch summary (also printed to the run log) lists the evidence: reason, commit,
dispatcher and approver(s), timestamps, the old volume's id/name/size/labels, emptiness and never-pooled verdicts, image and hash
equality, the delete and forget results, the readiness row, the escrow object facts and the new server id and location. It makes the
"provisioned, proof pending" claim only on a successful apply run.

Caveats: the token that reads the marker config is read/write today (a read-only token is a prerequisite on #9358); the web-class R2
pair the recovery check reads may be write-capable (#9461); the state bucket has no object versioning (#7992) and `terraform state rm`
detects a lost update only after the fact; the Doppler and Terraform-state copies of the passphrase share one blast radius. While
web-2 is being replaced, web-1 carries the watchdog dispatch clock alone and web-2's own heartbeat alert may fire: that is expected
for the window, not a fault.

## Closing checklist (a separate change; none of it ships with the workflow)

In this checklist "the closing change" is the later change made after the rebirth has run. The change that retired the escrow-create workflow and flipped the HALT (PR #9569) is called the retirement change.

| # | Step | Who |
|---|---|---|
| 1 | Copy the dispatch summary (run id, SHA, dispatcher, approver, timestamps) into the closing change: run logs expire | the engineer or agent landing the change |
| 2 | Flip the `hcloud_volume.workspaces` ledger row to `luks` (`live_verification: available`, `live_coverage_floor` 2 to 3), and supersede the Article 30 and compliance-posture sentences conditioned on this event with dated markers (the two cells stay byte-equal after bold removal). **No cell says "LUKS-backed at boot" before the graded reboot proof.** The flip has prerequisites that the retirement change (#9372) records and does not perform: split the `hcloud_volume.workspaces` ledger row per host (it also covers web-1's plaintext backstop), make `scripts/lint-encryption-posture.py` accept `[each.key]` bindings and a sibling-file secret pair, supersede Article 30 and the compliance-posture record, and raise `live_coverage_floor` from 2 to 3. **None of this is done before the dispatch: the row flip stays after the graded reboot proof.** | the CLO agent drafts, the owner holds a veto |
| 3 | Re-capture web-2's SSH host-key pin (`scripts/capture-web-2-host-key.sh`, which needs the new IP printed in the summary); `apply-deploy-pipeline-fix` fails closed until then. Re-enable the push-apply workflows only after that | the engineer, then the owner re-enables |
| 4 | UPDATE the existing follow-through directive on #6931 (`earliest=` to rebirth + 3 days, printed in the summary); do not add a second. The retirement change's post-merge step sets `earliest=2026-10-18T00:00:00Z` (decision date 2026-10-15 plus 3 days). **Go/no-go:** dispatch by 2026-10-15, so the 3-day soak fits the window that closes 2026-10-22. A later dispatch re-sets `earliest` from the actual rebirth time as a mandatory step of that dispatch; otherwise the exception on `hcloud_volume.workspaces` is extended citing #6931 | the engineer |
| 5 | Delete `web2-luks-rebirth.yml`, `scripts/web2-rebirth*.sh` and their tests, `tests/scripts/lib/web-host-rebirth-gate.sh`, `tests/scripts/lib/web2-rebirth-classify.sh`, the fixtures, the suite registrations and the `MAIN_ROOT_TF_WORKFLOWS` entry (census 4 to 3; it was 5 before the retirement change, 4 after), and record the use in ADR-263. The `scripts/web2-rebirth.test.sh` rows the retirement change adds go with it: a real-tree `flip-precondition yes` row that reads `MET`, and a sandbox `real absent` flip case. Also correct two comments the retirement change leaves stale, in that later change: the CONSUMERS comment on `DOPPLER_TOKEN_WORKSPACES_LUKS_MARKER` in `workspaces-luks-fresh-boot.tf` (it names only the verify workflow and the sweeper), and the comment in `apps/web-platform/infra/workspaces-luks-header-web.tf` that says the rotation HALT "lets a first create through" | the engineer |
| 6 | Decision date **2026-10-15**: the dispatch has run and the web-2 host is provisioned with the proof pending, or the encryption-posture exception on `hcloud_volume.workspaces` (expires 2026-10-22) is extended citing #6931. The ledger flip cannot be in review by then: it follows the graded reboot proof, which cannot pass before about 2026-10-18. The engineer prepares the extension by 2026-10-14, so the owner can decide on the day; if the exception is extended instead, re-set `earliest` on the #6931 directive in the same step, or the follow-through reports FAIL when its window closes on 2026-10-22 | the owner decides; the engineer prepares the extension |

## References

ADR-263 (addendum 2026-10-05), `.github/workflows/web2-luks-rebirth.yml`, `scripts/web2-rebirth.sh`, `tests/scripts/lib/web-host-rebirth-gate.sh`,
[web-host-replace.md](./web-host-replace.md), [web-host-birth.md](./web-host-birth.md), `knowledge-base/project/plans/2026-10-05-feat-web2-luks-rebirth-workflow-plan.md`.
