---
title: "Record the DC-2 and DC-3 operator decisions"
type: docs
brand_survival_threshold: none
---

# docs: record two operator decisions and propagate one mandate

This plan records decisions the operator already made. It changes no runtime
behaviour and is deployed to production like any other docs change.

### Network-Outage Deep-Dive determination (Phase 4.5)

The trigger substrings (`ssh`, `unreachable`, `timeout`) appear in this plan only
inside a resource identifier and inside quoted rationale about a pre-existing
condition. The plan proposes no SSH operation, no firewall or allowlist change,
no DNS/routing change, and no diagnosis of a connectivity symptom. L3 firewall,
L3 DNS/routing, L7 TLS/proxy and L7 application therefore have nothing to
verify — the checklist is not applicable rather than unverified. Recorded per
`hr-ssh-diagnosis-verify-firewall` so the skip is auditable.

## Notes

The live gate suite passes and the live-file probe still reports HOLD.
