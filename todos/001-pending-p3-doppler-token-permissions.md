---
status: pending
priority: p3
tags: [security, infrastructure]
---

# Restrict Doppler token file permissions

Both cloud-init.yml files write `DOPPLER_TOKEN` to `/etc/environment` which is world-readable (0644). Write to a restricted file instead (`/etc/doppler-token` with 0600) and use systemd `EnvironmentFile=` directive.

**Files:** `apps/web-platform/infra/cloud-init.yml`, `apps/telegram-bridge/infra/cloud-init.yml`
