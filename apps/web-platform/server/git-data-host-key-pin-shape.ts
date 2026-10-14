// The one shape a git-data host-key pin may take (#7226 / #5914, ADR-237).
//
// Its own module because two consumers need it and neither may import the other for it:
// `resolveGitDataHostKeyPin()` (git-data-replication.ts) validates the Doppler value, and
// `gitDataHostKeyTrust()` (git-auth.ts) refuses any pin that does not match it at the byte
// that becomes the known_hosts line. git-data-replication.ts already imports git-auth.ts,
// and test suites mock git-auth.ts wholesale, so the regex cannot live in either.
//
// Exactly one key of the expected algorithm: no host pattern, marker, comment or newline.
// The caller trims first, and the regex has NO `m` flag, so an embedded second line can
// never half-match. 68 base64 characters, no padding (a 51-byte ED25519 wire blob).
// # twin: apps/web-platform/infra/git-data-flag-precheck.sh,
// #       .github/actions/cf-tunnel-ssh-bridge/write-known-hosts.sh (ED25519 arm) and
// #       apps/web-platform/infra/modules/git-data-userdata/variables.tf carry the same
// #       shape check. Change them together.
export const GIT_DATA_HOST_KEY_PIN_RE = /^ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI[A-Za-z0-9+/]{43}$/;
