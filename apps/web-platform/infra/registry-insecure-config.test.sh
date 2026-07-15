#!/usr/bin/env bash
set -euo pipefail

# Drift guard for terraform_data.registry_insecure_config (#6122/ADR-096 Edge A, running
# hosts). This SSH provisioner delivers the canonical docker daemon.json (allowlisting the
# plain-HTTP private-net zot registry 10.0.1.30:5000 under insecure-registries) to the
# ALREADY-RUNNING web host and hot-reloads dockerd. HIGH-RISK: it mutates the prod docker
# daemon, so the reload-not-restart + malformed-JSON-guard invariants are load-bearing.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_TF="$DIR/server.tf"
DAEMON_JSON="$DIR/docker-daemon.json"
CLOUD_INIT="$DIR/cloud-init.yml"
WORKFLOW="$DIR/../../../.github/workflows/apply-web-platform-infra.yml"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  PASS: $1"; }
no()  { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }
assert() { if eval "$2"; then ok "$1"; else no "$1"; fi; }

echo "=== registry-insecure-config drift guard (#6122) ==="

# Extract the resource block: from its header to the next top-level `resource`/`#`/EOF.
BLOCK="$(awk '
  /^resource "terraform_data" "registry_insecure_config"/ { inb=1 }
  inb { print }
  inb && /^}/ { exit }
' "$SERVER_TF")"

assert "resource terraform_data.registry_insecure_config exists" \
  "[[ -n \"\$BLOCK\" ]]"

# triggers_replace MUST hash the standalone file (NOT an inline heredoc) so the trigger
# tracks the delivered content — inline strings desync the hash (integration learning).
assert "triggers_replace = sha256(file(docker-daemon.json))" \
  "printf '%s' \"\$BLOCK\" | grep -qE 'triggers_replace[[:space:]]*=[[:space:]]*sha256\(file\(\"\\\$\{path.module\}/docker-daemon.json\"\)\)'"

# The file provisioner delivers docker-daemon.json to /etc/docker/daemon.json.
assert "file provisioner delivers docker-daemon.json → /etc/docker/daemon.json" \
  "printf '%s' \"\$BLOCK\" | grep -qF 'destination = \"/etc/docker/daemon.json\"'"

# RELOAD, not restart: a restart bounces every running container mid-deploy. Anchor on
# the double-quoted inline-array form so an explanatory comment mentioning the command in
# `backticks` does not false-match (drift-guard-vs-comment-prose class).
assert "uses 'systemctl reload docker' (SIGHUP, not restart)" \
  "printf '%s' \"\$BLOCK\" | grep -qF '\"systemctl reload docker\"'"
assert "does NOT 'systemctl restart docker' (would bounce running containers)" \
  "! printf '%s' \"\$BLOCK\" | grep -qF '\"systemctl restart docker\"'"

# Malformed-JSON guard must precede the reload (a broken daemon.json bricks the daemon).
GUARD_LN=$(printf '%s\n' "$BLOCK" | grep -nF 'json.load' | head -1 | cut -d: -f1 || true)
RELOAD_LN=$(printf '%s\n' "$BLOCK" | grep -nF '"systemctl reload docker"' | head -1 | cut -d: -f1 || true)
assert "malformed-JSON guard (python3 json.load) present" "[[ -n \"\$GUARD_LN\" ]]"
assert "JSON guard precedes the docker reload" "[[ -n \"\$GUARD_LN\" && -n \"\$RELOAD_LN\" && \"\$GUARD_LN\" -lt \"\$RELOAD_LN\" ]]"

# every remote-exec inline block must open with `set -e` (also enforced globally by
# server-tf-set-e.test.sh; asserted here for locality).
assert "every remote-exec inline opens with 'set -e'" \
  "printf '%s\n' \"\$BLOCK\" | awk '/inline = \[/{n++} /\"set -e\"/{seen[n]=1} END{for(i=1;i<=n;i++) if(!seen[i]) exit 1}'"

# Post-reload assertion that dockerd honors the insecure registry.
assert "asserts dockerd honors 10.0.1.30:5000 after reload" \
  "printf '%s' \"\$BLOCK\" | grep -qF 'docker info' && printf '%s' \"\$BLOCK\" | grep -qF '10.0.1.30:5000'"

# The delivered daemon.json is valid JSON and allowlists the zot endpoint.
assert "docker-daemon.json exists" "[[ -f \"\$DAEMON_JSON\" ]]"
assert "docker-daemon.json is valid JSON" \
  "python3 -c 'import json; json.load(open(\"$DAEMON_JSON\"))'"
assert "docker-daemon.json lists 10.0.1.30:5000 under insecure-registries" \
  "python3 -c 'import json; d=json.load(open(\"$DAEMON_JSON\")); exit(0 if \"10.0.1.30:5000\" in d.get(\"insecure-registries\",[]) else 1)'"

# It is CI--target-ed (SSH-provisioned resources MUST be in the -target list, else they
# silently never apply — apply-path-cto-ruling.md condition #1).
assert "registry_insecure_config is in the workflow SSH -target list" \
  "grep -qF -- '-target=terraform_data.registry_insecure_config' \"\$WORKFLOW\""

# Fresh/running-host parity: cloud-init.yml writes its OWN inline daemon.json on fresh boot
# (task 3.0a) and this resource delivers docker-daemon.json to running hosts — both MUST
# allowlist the SAME zot endpoint, else a future IP change diverges the two host classes.
CI_ZOT_IP="$(grep -oE '"insecure-registries":[[:space:]]*\["[0-9.]+:[0-9]+"\]' "$CLOUD_INIT" | grep -oE '[0-9.]+:[0-9]+' | head -1 || true)"
DJ_ZOT_IP="$(python3 -c 'import json; print((json.load(open("'"$DAEMON_JSON"'")).get("insecure-registries") or [""])[0])' 2>/dev/null || true)"
assert "cloud-init inline daemon.json and docker-daemon.json agree on the zot endpoint (found ci='$CI_ZOT_IP' dj='$DJ_ZOT_IP')" \
  "[[ -n \"\$CI_ZOT_IP\" && \"\$CI_ZOT_IP\" == \"\$DJ_ZOT_IP\" ]]"

# --- #6483: the registry host's credential-convergence edges -----------------------------
# WEB-PLATFORM-5B root cause: /etc/zot/htpasswd is baked once at boot from the two Doppler
# tokens, but hcloud_server.registry's templatefile() passes only the non-secret USERNAMES —
# zero references to random_password.*.result. Terraform therefore has no data edge from the
# password to the host and cannot know the bake is stale, so a rotation updates both Doppler
# copies while the host keeps serving the old htpasswd. These guard the two edges that close
# it. Comments are stripped before matching so the guard can never pass on explanatory prose
# (the false-match class from 2026-06-03-drift-guard-assertion-false-passes-on-comment-prose).
ZOT_TF="$DIR/zot-registry.tf"

# Extract hcloud_server.registry's block, minus comment lines.
REG_BLOCK="$(awk '
  /^resource "hcloud_server" "registry"/ { inb=1 }
  inb { print }
  inb && /^}/ { exit }
' "$ZOT_TF" | grep -vE '^[[:space:]]*#')"

assert "hcloud_server.registry block extracted (non-empty)" \
  "[[ -n \"\$REG_BLOCK\" ]]"

# `[[:space:]]*=` not ` = `: terraform fmt re-aligns equals signs when a block gains an
# attribute, which would silently blind a single-space-anchored guard.
assert "hcloud_server.registry declares lifecycle.replace_triggered_by" \
  "printf '%s' \"\$REG_BLOCK\" | grep -qE 'replace_triggered_by[[:space:]]*=[[:space:]]*\['"

# Tolerate either HCL list form (one-per-line or inline) so `terraform fmt` collapsing or
# expanding the list cannot flip the guard; the comment strip above is what keeps this
# honest against prose that merely names the resource.
assert "replace_triggered_by names random_password.zot_pull (rotation re-bakes htpasswd)" \
  "printf '%s' \"\$REG_BLOCK\" | grep -qE 'random_password\.zot_pull[[:space:]]*(,|\]|\$)'"

assert "replace_triggered_by names random_password.zot_push" \
  "printf '%s' \"\$REG_BLOCK\" | grep -qE 'random_password\.zot_push[[:space:]]*(,|\]|\$)'"

# The host reads both tokens at boot via the Doppler CLI, so TF sees no implicit edge and is
# free to boot the server before the secret writes land — racing the htpasswd bake against
# the token write on a fresh stand-up. #6244 added the betterstack entry for exactly this
# reason and never generalized it to the two secrets that actually gate the bake.
for _s in registry_betterstack_logs_token zot_pull_token_registry zot_push_token_registry; do
  assert "hcloud_server.registry depends_on names doppler_secret.$_s" \
    "printf '%s' \"\$REG_BLOCK\" | grep -qE 'doppler_secret\.${_s}[[:space:]]*(,|\]|\$)'"
done

# The comment at zot-registry.tf:78-80 asserted a guarantee the code did not provide — a
# rotation updated Doppler and left the host's htpasswd untouched. That false comment is
# what let this ship; assert it is gone rather than merely contradicted.
assert "the false 'one apply re-propagates htpasswd' rotation claim is gone" \
  "! grep -qF 're-propagates htpasswd + Doppler in ONE apply' \"\$ZOT_TF\""

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
