# Pinned to v0.15.4 — first-stable line (0.15.x GA'd; the beta pin's
# "re-evaluate on first stable" note is now resolved). Bumped from
# v0.15.0-beta2 under #6636: on 2026-07-17 Sentry briefly returned 410
# "This API no longer exists" on the legacy issue-alert read endpoint,
# wedging the full-root plan. The durable fix is this bump: per the
# v0.15.3 release notes, PR jianyuan/terraform-provider-sentry#885 ("fix:
# Update reads from GET endpoint") switched sentry_issue_alert reads OFF the
# legacy endpoint, so v0.15.4 no longer depends on the retired read path.
# (This durability differentiator is changelog-sourced, not plan-measured:
# the 410 was transient — beta2 plans clean again now, so a terraform plan
# cannot observe it — but the bump future-proofs against the endpoint's
# eventual permanent retirement, per the standing deprecation warning.) The `sentry_alert` migration remains deferred: the resource
# is deprecated-but-functional and a faithful migration still requires
# monitor_ids binding — see ADR-031 §Amendment 2026-07-17. Provider
# source rationale + escape-hatch documented in
# knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md.
terraform {
  required_version = ">= 1.6"

  required_providers {
    sentry = {
      source  = "jianyuan/sentry"
      version = "0.15.4"
    }
  }
}
