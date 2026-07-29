# (#7025, R7) The RAW rendered cloud-config.
#
# Deliberately NOT base64gzip'd here. The caller wraps it, because the wrap is a
# host-attribute concern (Hetzner base64-decodes user_data before cloud-init sees it, so
# base64 is MANDATORY on this provider and base64gzip() is the intended path — ADR-080),
# while the RAW string is what a size harness needs to measure and what a diff between the
# two roots' renders would compare. Emitting only the wrapped form would force every
# consumer to un-gzip to inspect it.
#
# Deliberately NO `user_data_sha256` output. It would name a DIFFERENT quantity from
# RUNG2_TEMPLATE_SHA256 — a hash of the RENDER versus a hash of the SOURCE files — and two
# same-shaped hashes of different things one import away from each other is a maintenance
# trap, not a convenience.
output "rendered" {
  description = "The rendered cloud-init-git-data.yml, un-wrapped. The caller applies base64gzip()."
  value       = local.rendered
  sensitive   = true
}
