# Learning: Doppler Secrets Manager Setup Patterns

## Problem

Setting up Doppler as a centralized secrets manager for a project with secrets scattered across GitHub Actions, local `.env`, production server `.env`, and Terraform variables. Multiple integration patterns needed: CI sync, server runtime injection, local dev, Terraform.

## Solution

### CLI Installation Without sudo

The Doppler install script requires `dpkg`/`apt` (sudo). For non-root environments, download the binary directly:

```bash
mkdir -p ~/.local/bin
ARCH=$(uname -m) && case "$ARCH" in x86_64) ARCH="amd64";; aarch64) ARCH="arm64";; esac
curl -Ls "https://cli.doppler.com/download?os=linux&arch=${ARCH}&format=tar" | tar -xz -C ~/.local/bin doppler
```

### CLI Auth in Non-Interactive Shells

`doppler login` requires an interactive terminal (prompts for browser auth). In automation:
- Create a **Personal Token** from the Doppler dashboard (Tokens → Personal → Create)
- Configure CLI: `doppler configure set token <token> --scope /`

### Docker Env Injection — The Critical Pattern

`doppler run -- docker run` does NOT inject env vars into the container. Docker containers don't inherit the parent shell's environment. The correct pattern:

```bash
doppler secrets download --no-file --format docker --project soleur --config prd \
  | docker run --env-file /dev/stdin -d --name container-name image:tag
```

Or with fallback (for `set -euo pipefail` scripts):

```bash
resolve_env_file() {
  if command -v doppler >/dev/null 2>&1 && [[ -n "${DOPPLER_TOKEN:-}" ]]; then
    local tmpenv
    tmpenv=$(mktemp /tmp/doppler-env.XXXXXX)
    chmod 600 "$tmpenv"
    if doppler secrets download --no-file --format docker --project soleur --config prd > "$tmpenv" 2>/dev/null; then
      echo "$tmpenv"
      return 0
    fi
    rm -f "$tmpenv"
  fi
  echo "/mnt/data/.env"
}
```

### CI Sync vs Runtime Injection

For GitHub Actions, Doppler's **sync integration** is far simpler than runtime injection:
- Sync pushes secrets to GH Actions' native `secrets.*` store
- Zero workflow file changes needed — all `secrets.*` refs, `with:` inputs, `secrets: inherit` continue working
- Rotation is one command: update in Doppler, sync auto-pushes to GH

### GitHub Secret Values Are Not Readable

`gh secret list` returns names only. `gh secret get` doesn't exist. You cannot programmatically extract existing GitHub Actions secret values. Plan for this when migrating — you need the original sources (dashboards, server `.env`, etc.).

### hcloud CLI Auth

`hcloud context create --token` is wrong syntax. Use the environment variable instead:

```bash
export HCLOUD_TOKEN=<token>
hcloud server list
```

## Key Insight

The Doppler sync-to-GitHub approach eliminates the hardest CI migration problem (rewriting `with:` action inputs and `secrets: inherit` patterns). By letting Doppler push TO GitHub's native secrets store, all 14 workflow files work unchanged. The real engineering work is the server-side injection pattern, where the Docker env injection gotcha (`doppler run` doesn't pass env to containers) would have caused a silent production outage if not caught during plan review.

## Session Errors

1. `doppler login` EOF in non-interactive shell — resolved by using personal token auth
2. `install.sh | sh` needs sudo — resolved by direct binary download to `~/.local/bin`
3. Clipboard API returned stale value — user provided token manually
4. `hcloud context create --token` wrong syntax — resolved by using `HCLOUD_TOKEN` env var
5. `gh secret get` doesn't exist — GitHub only exposes secret names, not values

## Tags
category: integration-issues
module: infrastructure, ci, secrets-management
