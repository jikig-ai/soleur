---
status: pending
priority: p3
tags: [infrastructure, consistency]
---

# Align cloud-init runcmd ordering between servers

telegram-bridge installs cloudflared before Docker; web-platform does the reverse. Align ordering to reduce cognitive overhead when diffing.

**Files:** `apps/telegram-bridge/infra/cloud-init.yml`, `apps/web-platform/infra/cloud-init.yml`
