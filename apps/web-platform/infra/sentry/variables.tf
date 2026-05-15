variable "sentry_org" {
  type        = string
  description = "Sentry organization slug (e.g. jikigai)."
  default     = "jikigai"
}

variable "sentry_project" {
  type        = string
  description = "Sentry project slug for the Web Platform (e.g. web-platform)."
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
