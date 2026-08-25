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
# eventual permanent retirement, per the standing deprecation warning.)
#
# ^^ RETRACTED — see the 2026-08-20 correction below before believing the
#    paragraph above. The changelog datum it rests on is measured FALSE:
#    v0.15.4 still reads the deprecated path.
#
# The `sentry_alert` migration remains deferred: the resource
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
# which is exactly the inference recorded here.
#
# Corrected again 2026-08-20 (#7590): an earlier version of this note said "the
# bump remains the right fix for THIS root". That is retracted too. The
# durability rationale (v0.15.3 #885 moved sentry_issue_alert reads off the
# legacy endpoint) was changelog-sourced and never plan-measured. CI measured it
# with v0.15.4 installed: run 32362401543 (2026-08-20T11:09:07Z) took 410 on
# 29 of 29 sentry_issue_alert reads and failed terraform plan, while run
# 32362320701 one minute earlier passed. This pin is stable-over-beta and worth
# keeping, but it does NOT clear the 410 and this root still wedges on every
# brownout window.
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
