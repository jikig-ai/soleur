---
title: "Cloud Deploy: Infrastructure & SDK Integration Patterns"
category: integration-issues
tags: [terraform, cloud-init, websocket, hetzner, hcloud, bun, claude-code-sdk]
module: telegram-bridge
symptoms:
  - "Terraform hcloud_volume automount conflicts with cloud-init manual mount"
  - "cloud-init mkfs.ext4 -F destructively reformats pre-formatted volumes"
  - "Claude Code CLI WebSocket connection fails when server not yet listening"
date: 2026-02-10
---

# Learning: Cloud Deploy Infrastructure & SDK Integration

## Problem 1: Terraform + cloud-init Volume Mount Conflict

When using Hetzner Cloud volumes, setting both `hcloud_volume(format="ext4")` +
`hcloud_volume_attachment(automount=true)` alongside cloud-init manual mount
commands causes conflicts. `automount=true` adds the volume to fstab and mounts
it automatically; cloud-init then tries to mount the same device again.

Additionally, cloud-init scripts often include `mkfs.ext4 -F` which would
destructively reformat a volume that Terraform already formatted.

## Solution 1

Separate concerns: let Terraform format the volume (one-time), let cloud-init
handle mounting (idempotent).

```hcl
# server.tf -- NO automount
resource "hcloud_volume_attachment" "data" {
  volume_id = hcloud_volume.data.id
  server_id = hcloud_server.bridge.id
}
```

```yaml
# cloud-init.yml -- mount only, no mkfs
runcmd:
  - mkdir -p /mnt/data
  - mount /dev/disk/by-id/scsi-0HC_Volume_* /mnt/data || true
  - echo '/dev/disk/by-id/scsi-0HC_Volume_* /mnt/data ext4 defaults 0 2' >> /etc/fstab
```

## Problem 2: Claude Code --sdk-url WebSocket Protocol

The CLI connects as a WebSocket CLIENT to a server you provide. A race condition
exists: if the server is not listening when the CLI spawns, the CLI exits with a
connection error. A second-order dependency: the bridge must wait for the
`system/init` message before accepting user messages.

## Solution 2

Strict initialization order:

1. Start WebSocket server (`Bun.serve()` on 127.0.0.1:PORT)
2. Spawn CLI (`claude --sdk-url ws://127.0.0.1:PORT ...`)
3. Wait for `system/init` message, then set state to "ready"
4. Only relay Telegram messages when state is "ready"

Key protocol details:
- Protocol is NDJSON (newline-delimited JSON)
- CLI sends `system/init` as first message (handshake)
- Permission `control_response` MUST include `updatedInput` field for allow
- `result` message marks end of a conversation turn

## Key Insight

For Terraform + cloud-init: never mix automount with manual mount. Pick one
orchestrator for each concern. For the WebSocket protocol: the server must be
listening before the CLI spawns, and the `system/init` handshake must complete
before accepting traffic.

## Tags

category: integration-issues
module: telegram-bridge
