# Pinned to v0.15.0-beta2 — beta. Re-evaluate on first stable v0.15.0
# release. Provider source rationale + escape-hatch documented in
# knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md.
terraform {
  required_version = ">= 1.6"

  required_providers {
    sentry = {
      source  = "jianyuan/sentry"
      version = "0.15.0-beta2"
    }
  }
}
