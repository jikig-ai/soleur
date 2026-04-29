#!/usr/bin/env bash
set -euo pipefail

# Tests the seed sequence used by ci-deploy.sh and cloud-init.yml to populate
# /mnt/data/plugins/soleur from the image's baked plugin tree (#3045).
#
# Asserts:
#   - manifest (.claude-plugin/plugin.json) lands at the mount root, not nested
#     one extra level (the `src/.` trailing-dot is load-bearing per Sharp Edges)
#   - skill stub markdown survives the docker cp (plugin .md content is the
#     plugin's behavior — it MUST ship)
#   - prior-version dotfiles and regular files are removed by the cleanup glob
#     (otherwise stale `.claude-plugin/` from a previous deploy would persist)
#
# Skip cleanly if Docker is unavailable (CI runner without docker-in-docker).

if ! command -v docker >/dev/null 2>&1; then
  echo "SKIP: docker not available"
  exit 0
fi

if ! docker info >/dev/null 2>&1; then
  echo "SKIP: docker daemon not reachable"
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"; docker rm -f soleur-plugin-seed-test >/dev/null 2>&1 || true; docker rmi -f soleur-plugin-seed-test:fixture >/dev/null 2>&1 || true' EXIT

# Build a tiny fixture image with a synthetic plugin tree.
cat > "$TMP/Dockerfile" <<'EOF'
FROM busybox
RUN mkdir -p /opt/soleur/plugin/.claude-plugin && \
    echo '{"name":"soleur-test"}' > /opt/soleur/plugin/.claude-plugin/plugin.json && \
    mkdir -p /opt/soleur/plugin/skills/test && \
    echo "stub" > /opt/soleur/plugin/skills/test/SKILL.md
EOF
docker build -t soleur-plugin-seed-test:fixture "$TMP" >/dev/null

# Pre-populate the bind-mount target with stale content (regular file + dotfile +
# stale dotdir) to verify cleanup removes both visible and hidden entries.
TARGET="$TMP/mnt/data/plugins/soleur"
mkdir -p "$TARGET"
echo "stale" > "$TARGET/stale-file.txt"
mkdir -p "$TARGET/.stale-dir"
touch "$TARGET/.stale-dir/keep"

# Run the seed sequence verbatim (matches ci-deploy.sh — bash brace-glob).
docker create --name soleur-plugin-seed-test soleur-plugin-seed-test:fixture >/dev/null
rm -rf "$TARGET"/{*,.[!.]*,..?*} 2>/dev/null || true
docker cp soleur-plugin-seed-test:/opt/soleur/plugin/. "$TARGET/"
docker rm soleur-plugin-seed-test >/dev/null

# Assertions — fail loudly with concrete reason on each.
fail() { echo "FAIL: $1"; exit 1; }

[[ -f "$TARGET/.claude-plugin/plugin.json" ]] \
  || fail "manifest missing at $TARGET/.claude-plugin/plugin.json (docker cp src/. dst/ contract broken?)"
[[ -f "$TARGET/skills/test/SKILL.md" ]] \
  || fail "skill stub missing at $TARGET/skills/test/SKILL.md (.md content stripped by image build?)"
[[ ! -e "$TARGET/stale-file.txt" ]] \
  || fail "stale regular file remained at $TARGET/stale-file.txt (cleanup glob did not match *)"
[[ ! -e "$TARGET/.stale-dir" ]] \
  || fail "stale dotdir remained at $TARGET/.stale-dir (cleanup glob did not match .[!.]*)"

# Negative-space: the manifest must NOT land at $TARGET/plugin/.claude-plugin
# (which would happen if the trailing /. was dropped from `docker cp src dst`).
[[ ! -e "$TARGET/plugin" ]] \
  || fail "docker cp produced nested $TARGET/plugin/... — the trailing /. on the source argument was dropped"

echo "PASS: cloud-init-plugin-seed"
