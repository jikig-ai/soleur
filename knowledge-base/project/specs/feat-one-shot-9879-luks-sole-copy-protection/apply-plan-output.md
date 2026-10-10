# Evidence plan for the per-merge apply (#9879, Phase 0)

Read-only. Produced 2026-10-10T11:41Z at branch head `40b2aff031` (pins applied in the worktree). This file is a
projection only: no raw plan, no `terraform show -json` and no variable value is committed. Raw files stayed in the
session scratchpad and are deleted after this run.

## How it was produced

- Terraform 1.10.5 (the workflow's `TERRAFORM_VERSION`), checksum-verified; state read from the main root's R2 backend; `-lock=false`.
- `-target` list: extracted mechanically from the per-merge "Terraform plan (allow-list, non-SSH resources only)" step of
  `apply-web-platform-infra.yml` (188 entries). **NO `-target` on `hcloud_volume.inngest_redis_luks`** and none on
  `hcloud_server.inngest`. `logtail_exploration.inngest_luks_wrong_volume` is in the list.
- **Deviation, stated plainly:** 22 of the 188 targets are `github_*` resources (actions secrets, repository environments,
  deployment policies). The GitHub provider needs the Tier-B infra App key, which was not pulled (the go-ahead covered only
  `cf_api_token_r2` and `doppler_token_tf`), so the run used the remaining **166** targets. A first run with all 188 computed the
  same single volume update and then failed at provider configuration with "no decodeable PEM data found", so it exited non-zero. The excluded
  resources do not depend on the volume. CI plans all 188 with the Tier-B key.
- Credentials: Hetzner `HCLOUD_TOKEN_READONLY` as `TF_VAR_hcloud_token` (asserted present, no fallback to a read/write
  token); `cf_api_token_r2` and `doppler_token_tf` from `soleur-infra-privileged/prd` (authorized by the operator for this
  plan only); backend keys from `prd_terraform`. Injected through the environment, never printed. A throwaway ssh public key
  satisfied `var.ssh_key_path`.

## Result

Plan summary line: `Plan: 0 to add, 1 to change, 0 to destroy.` (exit code 0). Plan entries: 172 (171 no-op, 0 read, 1 update).

Redacted human plan block for the one change:

```text
  # hcloud_volume.inngest_redis_luks will be updated in-place
  ~ resource "hcloud_volume" "inngest_redis_luks" {
      ~ delete_protection = false -> true
        id                = "106903269"
        name              = "soleur-inngest-redis-store-luks"
        # (5 unchanged attributes hidden)
    }

Plan: 0 to add, 1 to change, 0 to destroy.
```

| address | actions | delete_protection before | after |
|---|---|---|---|
| hcloud_volume.inngest_redis_luks | update | false | true |

Every other plan entry is `no-op` or `read`. `hcloud_server.inngest` has no entry. No entry names volume 106443278.

## Per-merge guard replay (same jq filter and halt conditions the workflow uses)

```json
{"plan_ok":true,"resource_deletes":0,"nested_deletes":0,"reboot_updates":0,"host_creates":0,"non_terraform_data_deletes":0,"apex_move_orphans":0,"undecidable_entries":0,"luks_passphrase_rotations":0,"web2_retire_out_of_scope_changes":1,"web2_server_destroyed":0,"web2_server_network_destroyed":0,"web2_volume_attachment_destroyed":0,"web2_volume_destroyed":0,"retire_firewall_attachment_updates":0,"retire_firewall_attachment_deletes":0}
```

Halt conditions from the workflow, evaluated over these counters: undecidable_entries 0, luks_passphrase_rotations 0,
host_creates 0, apex_move_orphans 0, destroy_count (resource_deletes + nested_deletes + reboot_updates) 0, plan_ok true. All pass.
`web2_retire_out_of_scope_changes` reads 1 because the volume update is outside the web-2 retirement allow-list; that counter
is read only by the web-2 retire dispatch, not by the per-merge job (grep of the workflow: no consumer).

## What this proves, and what it does not

Proved: the volume rides the per-merge plan as a dependency of a targeted resource, with exactly one in-place update and nothing
else, so the merge's own apply delivers delete protection. Not proved: that Hetzner refuses a delete (read-back after apply
does that), that the 22 excluded GitHub resources are unchanged (not influenced by this change), or that detach works under
protection (first sanctioned host replace is the live proof).
