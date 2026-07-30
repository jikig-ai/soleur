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

# (#7025, R7 follow-through) The arch token this render selected.
#
# Exported so the caller's phantom/wrong-arch precondition validates the arch that was
# ACTUALLY used to pick the binary, rather than a SECOND ternary the caller keeps equal to
# this one by convention. That copy was introduced by R7 itself — `modules/` does not exist on
# origin/main — and policing it needed four bash arms comparing two ternaries as text.
#
# BUT NOT BECAUSE "ONE TERNARY CANNOT DIVERGE FROM ITSELF". No suite reads THIS FILE: A16 and
# A18 read main.tf, A16b reads the caller. A second ternary here is expressible today. What
# makes a wrong value non-viable is the caller's precondition, which compares this output
# against `data.hcloud_server_type.git_data.architecture` — the live Hetzner catalog for the
# same var — so a wrong derivation wedges the plan instead of booting. The honest claim is
# "self-validating against ground truth", not "structurally unique".
#
# This is NOT the `user_data_sha256` case rejected above. That output would have named a
# DIFFERENT quantity from an existing same-shaped hash; `arch` names the SAME quantity the
# caller was recomputing, which is the inverse — it removes a near-duplicate rather than
# adding one.
#
# Not sensitive: it is `amd64` or `arm64`, and the precondition's error_message already
# prints it.
output "arch" {
  description = "The Doppler CLI download arch token (amd64|arm64) derived from var.git_data_server_type. The caller's wrong-arch precondition reads THIS, so the arch it validates and the arch the render downloads cannot diverge."
  value       = local.git_data_arch
}
