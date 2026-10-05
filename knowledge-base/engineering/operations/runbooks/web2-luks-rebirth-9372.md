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
2. Both push-apply workflows are paused and idle: `apply-web-platform-infra.yml` and `apply-deploy-pipeline-fix.yml` are
   `disabled_manually`, with nothing queued or running (an apply run refuses otherwise).
3. `image_tag` is a release built from a commit that carries the fresh-boot provisioner, and the coherence preflight proves
   the image's baked host-scripts hash equals `local.host_scripts_content_hash` at the dispatch commit.
4. `bash scripts/web-host-escrow-preflight.sh` is green (the workflow runs it first, before any Terraform command or Hetzner call).

## Dispatch

Plan first (the default; no write of any kind):

```bash
gh workflow run web2-luks-rebirth.yml --ref main \
  -f confirm=REBIRTH-web-2-LUKS -f expected_volume_id=106466179 -f image_tag=<vX.Y.Z> -f plan_only=true -f reason='<why>'
```

Read the run summary and the classifier verdict. Only after the owner approves **that** apply, dispatch with `-f plan_only=false`
and approve the `web-platform-infra-apply` environment gate. Confirm the run actually started: the shared concurrency
group keeps one running and one pending run, and a queued run can displace an older pending one.

## The classifier: what each verdict means

Every dispatch starts by classifying Hetzner and Terraform state. The run writes nothing until the verdict is `proceed` or a
`heal:` window. A `refuse:` ends the run RED before any write.

| Verdict | What is true | What the run does |
|---|---|---|
| `proceed` | the pinned ext4 volume is attached to web-2 and held by state | full path |
| `heal:detach_done` | detached last time | continues at DELETE |
| `heal:delete_done` | volume gone (404), state still holds it | continues at `state rm` |
| `heal:state_rm_done` | state is clean, the old server exists | continues at the `post` plan |
| `heal:apply_midway` | volume and server both gone | the `post` plan creates both |
| `heal:volume_created` | the raw volume exists in state, not attached | the `post-heal` plan |
| `refuse:already_reborn` | state holds another volume attached to web-2 | **single use**: a second rebirth needs a new reviewed pin and PR |
| `refuse:orphan_raw_volume` | a raw volume with the name exists and state does not hold it | delete it by the same pinned API path in a reviewed re-dispatch; never import by hand |
| `refuse:pinned_volume_not_the_empty_plaintext_one` | the pin is not ext4, or its name/labels differ | stop; the premise is false |
| `refuse:pinned_volume_attached_elsewhere`, `refuse:web2_holds_another_volume`, `refuse:duplicate_volume_name`, `refuse:state_*` | the world does not match the contract | stop and read the classifier line in the log |
| `refuse:push_apply_pause_not_real` | a push apply could re-create a plaintext volume | pause both workflows, wait for idle, re-dispatch |

A **failed boot is not healed here**: use `web_host_replace` for web-2 (it carries the new volume forward by design).
**There is no escrow retry.** While the host is still empty, an `escrow=missing` birth can only be redone by a second
rebirth, which `refuse:already_reborn` blocks; that needs a new reviewed pin.

## What the run proves, and what it does not

Evidence before any write, all read without SSH: 7 days of Better Stack `host_metrics` used-bytes for `/mnt/data`
(hour coverage, freshness, a 1 GiB ceiling, and a 15 to 21.5 GB total so a mis-mounted root disk cannot pass), the soak
marker absent by exact-name membership over secret **names**, the Hetzner volume still ext4 with the pinned id, name and labels.
The Better Stack JSON paths and the `dm-*` exclusion in `vector.toml` are **unconfirmed until the first live query**; an
absent field fails closed.

After the apply: a `SOLEUR_FRESH_BOOT_READY` row newer than the run with `luks=1 luks_arm=formatted escrow=ok`; a read-only
birth-time consistency check of the escrowed header and the two passphrase copies (`restore NOT exercised; open until #7992
and a restore drill`); then an hcloud reboot is **issued**. The run never claims the volume reopens: the proof is a later
luks-monitor probe row on a `boot_id` other than the readiness row's, `crypto_LUKS` on `/dev/mapper/workspaces`, graded by
`scripts/followthroughs/web2-luks-live-6931.sh` (enrolled on #6931 with `earliest` = rebirth + 3 days) and required by the soak
marker. Until then web-2 is *provisioned, proof pending*, at weight 0, holding no workspace data.

Caveats: the token that reads the marker config is read/write today (a read-only token is a prerequisite on #9358); the web-class
R2 pair the recovery check reads may be write-capable (#9461); the state bucket has no object versioning (#7992); the Doppler and
Terraform-state copies of the passphrase share one blast radius.

## Closing checklist (a separate change; none of it ships with the workflow)

1. Copy the dispatch summary (run id, SHA, actor, approver, timestamps) into the closing change: run logs expire.
2. Flip the `hcloud_volume.workspaces` ledger row to `luks` (`live_verification: available`, `live_coverage_floor` 2 to 3), and
   supersede the Article 30 and compliance-posture sentences conditioned on this event with dated markers (the CLO agent
   owns the wording; the two cells stay byte-equal after bold removal). **No cell says "LUKS-backed at boot" before the graded reboot proof.**
3. Re-capture web-2's SSH host-key pin (`scripts/capture-web-2-host-key.sh`); `apply-deploy-pipeline-fix` fails closed until then.
   Re-enable the push-apply workflows only after that.
4. Enrol the follow-through directive on #6931 (printed in the dispatch summary).
5. Delete `web2-luks-rebirth.yml`, `scripts/web2-rebirth*.sh` and their tests, `tests/scripts/lib/web-host-rebirth-gate.sh`,
   `tests/scripts/lib/web2-rebirth-classify.sh`, the fixtures, the suite registrations and the `MAIN_ROOT_TF_WORKFLOWS` entry (census 5 to 4), and record the use in ADR-263.
6. Decision date **2026-10-15**: the dispatch has run and the ledger flip is in review, or the encryption-posture exception on
   `hcloud_volume.workspaces` (expires 2026-10-22) is extended citing #6931.

## References

ADR-263 (addendum 2026-10-05), `.github/workflows/web2-luks-rebirth.yml`, `scripts/web2-rebirth.sh`, `tests/scripts/lib/web-host-rebirth-gate.sh`,
[web-host-replace.md](./web-host-replace.md), [web-host-birth.md](./web-host-birth.md), `knowledge-base/project/plans/2026-10-05-feat-web2-luks-rebirth-workflow-plan.md`.
