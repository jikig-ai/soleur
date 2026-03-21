---
status: pending
priority: p3
tags: [infrastructure, observability]
---

# Add health endpoint for telegram-bridge through tunnel

The telegram-bridge health endpoint (`localhost:8080/health`) is not publicly accessible. Add a second tunnel ingress rule (e.g., `health-bridge.soleur.ai -> http://localhost:8080/health`) so CI can verify deploys the same way web-platform does.

**Files:** `apps/telegram-bridge/infra/tunnel.tf`, `.github/workflows/telegram-bridge-release.yml`
