# Vector agent IaC — observability shipper from Hetzner journald + host
# metrics to Better Stack Logs. Co-located with inngest-server.service; installed by
# the same `inngest-bootstrap.sh` script (single bootstrap surface; no
# new OCI image or sudoers entry).
#
# Version + sha256 pin live here so bumps land in IaC commits and survive
# operator audit. Bootstrap script reads both via env (templated by the
# OCI build OR cloud-init substitution, same pattern as
# INNGEST_CLI_VERSION + INNGEST_CLI_SHA256).

locals {
  # https://github.com/vectordotdev/vector/releases
  vector_version = "0.43.1"
  # sha256 of `vector-0.43.1-x86_64-unknown-linux-musl.tar.gz`
  # Verify before bump: curl -sL https://packages.timber.io/vector/${V}/vector-${V}-x86_64-unknown-linux-musl.tar.gz | sha256sum
  vector_sha256 = "8a3cc62d18ec88bb8433159d1d3455d3c77fefff73ce46d4f8cc464e100f65f1"
  # sha256 of `vector-0.43.1-aarch64-unknown-linux-musl.tar.gz` — the dedicated arm64
  # Inngest host (cax11, #6197). Consumed via templatefile (inngest-host.tf) as the
  # VECTOR_CLI_SHA256 OVERRIDE, mirroring inngest_cli_sha256_arm64 (inngest.tf:32-36).
  # Verify before bump: curl -sL https://packages.timber.io/vector/${V}/vector-${V}-aarch64-unknown-linux-musl.tar.gz | sha256sum
  vector_sha256_arm64 = "365bab73244780083eb95b3e42161a9179f23a0811ffa6180f613c3af06ed8e6"
}

# vector.toml is embedded into the inngest-bootstrap.sh script at build
# time (same shape as the systemd unit heredoc). The config file lives in
# this directory so version control and reviewer-agent linters see it
# alongside the rest of the Hetzner IaC. The bootstrap script reads it via
# the OCI image's `_files/` directory OR via cloud-init's write_files
# stanza (both deliver `vector.toml` to `/etc/vector/vector.toml`).
#
# A separate `vector.service` systemd unit and the install/extract logic
# live inside `inngest-bootstrap.sh` itself — same idempotency contract
# (sha256-verify download → install → version-pin file → systemctl
# daemon-reload + enable + restart).
