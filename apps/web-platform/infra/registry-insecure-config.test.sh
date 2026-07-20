#!/usr/bin/env bash
set -euo pipefail

# Drift guard for terraform_data.registry_insecure_config (#6122/ADR-096 Edge A, running
# hosts). This SSH provisioner delivers the canonical docker daemon.json (allowlisting the
# plain-HTTP private-net zot registry under insecure-registries) to the ALREADY-RUNNING web
# host and hot-reloads dockerd. HIGH-RISK: it mutates the prod docker daemon, so the
# reload-not-restart + malformed-JSON-guard invariants are load-bearing.
#
# #6448: the allowlisted endpoint is now DERIVED from local.registry_endpoint (the single
# source, zot-registry.tf:44) via docker-daemon.json.tmpl — NOT a hardcoded copy. This guard
# proves the derivation wiring and, via a shape-based residual scan, that no hardcoded IP:5000
# copy has been reintroduced on the derivation surface. The old guard was self-referential: it
# grepped the delivered file for the literal it itself hardcoded, so it could never detect a
# drift from the local — the exact defect #6448 fixes.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_TF="$DIR/server.tf"
TMPL="$DIR/docker-daemon.json.tmpl"
CLOUD_INIT="$DIR/cloud-init.yml"
WORKFLOW="$DIR/../../../.github/workflows/apply-web-platform-infra.yml"

# Interpolation tokens the derivation surface MUST carry (single-quoted so the shell never
# expands them; every assert greps them as fixed strings).
ENDPOINT_VAR='${registry_endpoint}'
PROBE_TOKEN='${local.registry_endpoint}'

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  PASS: $1"; }
no()  { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }
assert() { if eval "$2"; then ok "$1"; else no "$1"; fi; }

echo "=== registry-insecure-config drift guard (#6122 / #6448) ==="

# Extract the resource block: from its header to the next top-level `}`.
BLOCK="$(awk '
  /^resource "terraform_data" "registry_insecure_config"/ { inb=1 }
  inb { print }
  inb && /^}/ { exit }
' "$SERVER_TF")"

assert "resource terraform_data.registry_insecure_config exists" \
  "[[ -n \"\$BLOCK\" ]]"

# --- #6448 structural wiring: the delivered daemon.json DERIVES from local.registry_endpoint ---

# local.docker_daemon_json renders the .tmpl, passing registry_endpoint = local.registry_endpoint.
assert "local.docker_daemon_json = templatefile(docker-daemon.json.tmpl, {...})" \
  "grep -qE 'docker_daemon_json[[:space:]]*=[[:space:]]*templatefile\(\"\\\$\{path.module\}/docker-daemon.json.tmpl\"' \"\$SERVER_TF\""

# The endpoint var must be threaded into BOTH templatefile maps — running-host
# (docker-daemon.json.tmpl) AND fresh-host (cloud-init.yml). Scope each assertion to its OWN map
# block (extract from the templatefile("...<file>...") line to the block's closing `})`), NOT a
# file-wide count: a bare `count >= 2` could pass vacuously if one map dropped the var while an
# unrelated occurrence appeared elsewhere (cq-assert-anchor-not-bare-token). Each awk bounds at
# the first `}` immediately followed by `)` after the templatefile line — the map close (`})`) or
# the base64gzip-wrapper close (`}))`). No inner `})` occurs in either map body.
DJ_MAP="$(awk '/docker-daemon\.json\.tmpl"/{f=1} f{print} f && /\}\)/{exit}' "$SERVER_TF")"
CI_MAP="$(awk '/cloud-init\.yml"/{f=1} f{print} f && /\}\)/{exit}' "$SERVER_TF")"
assert "docker-daemon.json.tmpl map passes registry_endpoint = local.registry_endpoint (running-host)" \
  "printf '%s' \"\$DJ_MAP\" | grep -qE 'registry_endpoint[[:space:]]*=[[:space:]]*local\.registry_endpoint'"
assert "cloud-init.yml map passes registry_endpoint = local.registry_endpoint (fresh-host)" \
  "printf '%s' \"\$CI_MAP\" | grep -qE 'registry_endpoint[[:space:]]*=[[:space:]]*local\.registry_endpoint'"

# triggers_replace hashes the RENDERED content (local.docker_daemon_json), NOT sha256(file(...)).
# The static-file hash could never track a derived value; the rendered-string hash does.
assert "triggers_replace = sha256(local.docker_daemon_json)" \
  "printf '%s' \"\$BLOCK\" | grep -qE 'triggers_replace[[:space:]]*=[[:space:]]*sha256\(local\.docker_daemon_json\)'"
assert "triggers_replace no longer hashes a static file() copy" \
  "! printf '%s' \"\$BLOCK\" | grep -qE 'sha256\(file\('"

# The file provisioner delivers the RENDERED content (content=), not a static source= copy.
assert "file provisioner uses content = local.docker_daemon_json (rendered, not source=)" \
  "printf '%s' \"\$BLOCK\" | grep -qE 'content[[:space:]]*=[[:space:]]*local\.docker_daemon_json'"
assert "file provisioner does NOT source a static docker-daemon.json" \
  "! printf '%s' \"\$BLOCK\" | grep -qE 'source[[:space:]]*=[[:space:]]*\"\\\$\{path.module\}/docker-daemon.json'"
assert "file provisioner delivers → /etc/docker/daemon.json" \
  "printf '%s' \"\$BLOCK\" | grep -qF 'destination = \"/etc/docker/daemon.json\"'"

# RELOAD, not restart: a restart bounces every running container mid-deploy. Anchor on the
# double-quoted inline-array form so an explanatory comment mentioning the command in
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

# Post-reload probe DERIVES the endpoint — it interpolates \${local.registry_endpoint}, NOT a
# hardcoded literal. Anchor on the interpolation token so a re-hardcoded literal fails.
assert "post-reload probe interpolates \${local.registry_endpoint} (not a hardcoded literal)" \
  "printf '%s' \"\$BLOCK\" | grep -qF 'docker info' && printf '%s' \"\$BLOCK\" | grep -qF \"\$PROBE_TOKEN\""

# --- #6448 template shape: the .tmpl derives its allowlist value; the rendered doc is valid JSON ---
assert "docker-daemon.json.tmpl exists (renamed from the static docker-daemon.json)" \
  "[[ -f \"\$TMPL\" ]]"
assert "docker-daemon.json.tmpl insecure-registries value is \${registry_endpoint} (derived)" \
  "grep -q 'insecure-registries' \"\$TMPL\" && grep -qF \"\$ENDPOINT_VAR\" \"\$TMPL\""
# Rendered (not raw) JSON validity: the raw .tmpl holds the placeholder string; render it with
# the current endpoint value and confirm valid JSON (learning 2026-05-06: assert the rendered
# value, not the raw source, for anything interpolated). Full-render JSON validity in CI is also
# covered by validate-infra-templates.sh (Phase 7) — this is the locally-runnable mirror.
assert "rendered docker-daemon.json.tmpl is valid JSON" \
  "sed 's/\${registry_endpoint}/10.0.1.30:5000/' \"\$TMPL\" | python3 -c 'import json,sys; json.load(sys.stdin)'"

# --- #6448 cloud-init derivation: the fresh-host inline daemon.json derives too ---
assert "cloud-init.yml insecure-registries value is \${registry_endpoint} (derived)" \
  "grep -qE 'insecure-registries.*\\\$\{registry_endpoint\}' \"\$CLOUD_INIT\""

# --- #6448 THE mutation test: shape-based single-source residual scan (renumber-proof) ---
# Count NON-COMMENT occurrences of any hardcoded endpoint literal of the SHAPE IP:5000 across
# the whole derivation surface (docker-daemon.json.tmpl + cloud-init.yml + server.tf) and assert
# ZERO. Every consumer must interpolate the endpoint var; the ONLY legitimate place the :5000
# suffix is constructed is zot-registry.tf:44 (local.registry_endpoint =
# "${local.registry_private_ip}:5000"). A reintroduced hardcoded copy — the exact #6448 drift
# (local.registry_private_ip moves to .31 while a consumer keeps a .30:5000 copy) — is a
# non-comment IP:5000 literal, so this scan goes RED. The OLD guard could never fail this way (it
# grepped the file against its own copy). Match by SHAPE, NOT the pinned value 10.0.1.30:5000, so
# the guard stays load-bearing after a real subnet renumber (learning 2026-06-11 extract-by-shape;
# closes the architecture-review value-coupling advisory). Comment-strip ^[^#]* for HCL/YAML; the
# .tmpl is JSON (no comments). Adapts private-nic-guard.test.sh's non-comment LIVE_LITERALS scan.
# `{ grep … || true; }`: a zero-match grep (the SUCCESS path here — no hardcoded literal) exits
# 1, and under `set -euo pipefail` that would abort the script mid-run instead of yielding
# RESID=0. Contain the failure inside the pipe segment so wc still counts an empty stream.
RESID=$({ grep -rhE '^[^#]*[0-9]{1,3}(\.[0-9]{1,3}){3}:5000' \
  "$TMPL" "$CLOUD_INIT" "$SERVER_TF" || true; } | wc -l | tr -d ' ')
assert "no hardcoded IP:5000 literal on the derivation surface (.tmpl/cloud-init/server.tf) — all derive from local.registry_endpoint (found $RESID)" \
  "[[ \"\$RESID\" == \"0\" ]]"

# It is CI--target-ed (SSH-provisioned resources MUST be in the -target list, else they
# silently never apply — apply-path-cto-ruling.md condition #1).
assert "registry_insecure_config is in the workflow SSH -target list" \
  "grep -qF -- '-target=terraform_data.registry_insecure_config' \"\$WORKFLOW\""

# --- #6497: the registry host's credential-convergence edges -----------------------------
# WEB-PLATFORM-5B root cause: /etc/zot/htpasswd is baked once at boot from the two Doppler
# tokens, but hcloud_server.registry's templatefile() passes only the non-secret USERNAMES —
# zero references to random_password.*.result. Terraform therefore has no data edge from the
# password to the host and cannot know the bake is stale, so a rotation updates both Doppler
# copies while the host keeps serving the old htpasswd. These guard the two edges that close
# it. Comments are stripped before matching so the guard can never pass on explanatory prose
# (the false-match class from 2026-06-03-drift-guard-assertion-false-passes-on-comment-prose).
ZOT_TF="$DIR/zot-registry.tf"

# Extract hcloud_server.registry's block, stripping BOTH full-line comments AND trailing ones.
# The trailing strip is load-bearing, not tidiness: a first draft of this guard stripped only
# full-line prose, and a mutation with ZERO lifecycle/depends_on but the tokens named in
# TRAILING comments (`n2 = "x" # random_password.zot_pull,`) passed 22/22 green. zot-registry.tf
# uses trailing comments elsewhere, so the idiom is live in this very file.
# The col-0 `}` terminator is guaranteed by `terraform fmt -check -recursive .`
# (.github/workflows/infra-validation.yml) — without that gate an indented closing brace would
# let this awk over-collect into the next resource block.
REG_BLOCK="$(awk '
  /^resource "hcloud_server" "registry"/ { inb=1 }
  inb { print }
  inb && /^}/ { exit }
' "$ZOT_TF" | grep -vE '^[[:space:]]*#' | sed 's/[[:space:]]#.*$//')"

assert "hcloud_server.registry block extracted (non-empty)" \
  "[[ -n \"\$REG_BLOCK\" ]]"

# `[[:space:]]*=` not ` = `: terraform fmt re-aligns equals signs when a block gains an
# attribute, which would silently blind a single-space-anchored guard.
assert "hcloud_server.registry declares lifecycle.replace_triggered_by" \
  "printf '%s' \"\$REG_BLOCK\" | grep -qE 'replace_triggered_by[[:space:]]*=[[:space:]]*\['"

# Scope each assertion to the ATTRIBUTE it names, not the whole ~90-line resource block. A
# block-wide grep only proves the token appears SOMEWHERE in the resource — so moving
# random_password.zot_pull out of replace_triggered_by and into depends_on (a plausible
# tidy-up) left the suite 22/22 green while the assertion literally named
# "replace_triggered_by names random_password.zot_pull" was FALSE, and rotating the PULL token
# — the exact WEB-PLATFORM-5B credential — no longer replaced the host. The bug this file
# guards was fully reintroduced under a green guard. An assertion must pin the thing its own
# name claims.
RTB_LIST="$(printf '%s\n' "$REG_BLOCK" | awk '/replace_triggered_by[[:space:]]*=[[:space:]]*\[/{f=1} f{print} f && /\]/{exit}')"
DEP_LIST="$(printf '%s\n' "$REG_BLOCK" | awk '/^[[:space:]]*depends_on[[:space:]]*=[[:space:]]*\[/{f=1} f{print} f && /\]/{exit}')"

assert "replace_triggered_by list body extracted (non-empty)" "[[ -n \"\$RTB_LIST\" ]]"
assert "depends_on list body extracted (non-empty)" "[[ -n \"\$DEP_LIST\" ]]"

# List-form tolerant (one-per-line or inline) so terraform fmt collapsing/expanding the list
# cannot flip the guard.
assert "replace_triggered_by names random_password.zot_pull (rotation re-bakes htpasswd)" \
  "printf '%s' \"\$RTB_LIST\" | grep -qE 'random_password\.zot_pull[[:space:]]*(,|\]|\$)'"

assert "replace_triggered_by names random_password.zot_push" \
  "printf '%s' \"\$RTB_LIST\" | grep -qE 'random_password\.zot_push[[:space:]]*(,|\]|\$)'"

# The host reads both tokens at boot via the Doppler CLI, so TF sees no implicit edge and is
# free to boot the server before the secret writes land — racing the htpasswd bake against
# the token write on a fresh stand-up. #6244 added the betterstack entry for exactly this
# reason and never generalized it to the two secrets that actually gate the bake.
for _s in registry_betterstack_logs_token zot_pull_token_registry zot_push_token_registry; do
  assert "hcloud_server.registry depends_on names doppler_secret.$_s" \
    "printf '%s' \"\$DEP_LIST\" | grep -qE 'doppler_secret\.${_s}[[:space:]]*(,|\]|\$)'"
done

# The comment at zot-registry.tf:78-80 asserted a guarantee the code did not provide — a
# rotation updated Doppler and left the host's htpasswd untouched. That false comment is
# what let this ship; assert it is gone rather than merely contradicted.
assert "the false 'one apply re-propagates htpasswd' rotation claim is gone" \
  "! grep -qF 're-propagates htpasswd + Doppler in ONE apply' \"\$ZOT_TF\""

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
