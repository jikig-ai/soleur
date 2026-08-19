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
#
# Superseded 2026-08-19 (#7590): "the 410 was transient" above is the
# 2026-07-17 reading, kept as the dated measurement it was — the re-probe
# genuinely did come back clean. It was not transient. Sentry deprecated this
# API family on 2026-05-14 and serves it under scheduled BROWNOUTS: 410 for a
# window on a recurring schedule, 200 the rest of the time. A follow-up probe
# minutes later cannot distinguish "restored" from "outside the next window",
# which is exactly the inference recorded here. The bump remains correct and
# remains the right fix for THIS root; only the transience claim is retracted.
# Read ADR-031 §Amendment 2026-08-19 (#7590) before acting on the paragraph
# above.
terraform {
  required_version = ">= 1.6"

  required_providers {
    sentry = {
      source  = "jianyuan/sentry"
      version = "0.15.4"
    }
  }
}
