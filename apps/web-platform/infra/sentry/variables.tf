variable "sentry_org" {
  type        = string
  description = "Sentry organization slug. New DE org per Branch C (PR-β of #3861): `jikigai-eu`. The `jikigai` slug was taken on eu.sentry.io (TR3 302 probe 2026-05-17); the `-eu` suffix is the Branch-C precedent rename."
  default     = "jikigai-eu"
}

variable "sentry_project" {
  type        = string
  description = "Sentry project slug for the Web Platform. Renamed to `web-platform` on the new DE org per Branch C — was `soleur-web-platform` on the phantom-ingest org pre-2026-05-17."
  default     = "web-platform"
}

variable "sentry_region" {
  type        = string
  description = "Sentry region: 'de' (EU/Frankfurt) or 'us'. Soleur is DE per Article 30 PA8 §(e)."
  default     = "de"
  validation {
    condition     = contains(["de", "us"], var.sentry_region)
    error_message = "sentry_region must be 'de' or 'us'."
  }
}
