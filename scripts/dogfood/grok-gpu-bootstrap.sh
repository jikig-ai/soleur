#!/usr/bin/env bash
# #6546 — Thin idempotent bootstrap for Phase 2 open-weight dogfood on Hetzner Robot GEX44.
# Approach A: Grok CLI + Ollama co-located; Ollama bound to loopback only.
#
# Usage (as root on the GEX host — copy script first if repo not yet cloned):
#   scp scripts/dogfood/grok-gpu-bootstrap.sh root@<gex-ip>:/tmp/
#   ssh root@<gex-ip> 'bash /tmp/grok-gpu-bootstrap.sh'
#   bash /tmp/grok-gpu-bootstrap.sh --model qwen2.5-coder:32b --license-ok
#
# Does NOT order hardware. Does NOT pull a model without --license-ok.
# <!-- verified: 2026-07-17 source: https://docs.ollama.com/api/openai-compatibility OLLAMA_HOST pattern -->
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/dogfood/assert-ollama-loopback.sh
if [[ -f "${SCRIPT_DIR}/assert-ollama-loopback.sh" ]]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/assert-ollama-loopback.sh"
else
  # When scp'd alone to /tmp, inline minimal fail-closed assert.
  assert_ollama_loopback_listen() {
    local port=11434
    command -v ss >/dev/null 2>&1 || die "ss (iproute2) required for loopback exclusivity assert"
    if ss -lnt 2>/dev/null | grep -E "[:.]${port}\\b" | grep -qE "0\\.0\\.0\\.0:${port}|\\*:${port}|\\[::\\]:${port}"; then
      die "Ollama appears bound to a public interface (0.0.0.0/:: on :${port}) — Approach A requires loopback only"
    fi
  }
  assert_config_base_url_loopback() { return 0; }
fi

LICENSE_OK=0
MODEL=""
SKIP_CLONE=0
DOGFOOD_USER="${DOGFOOD_USER:-dogfood}"
WORKSPACE="${WORKSPACE:-/home/${DOGFOOD_USER}/soleur}"
LOG_DIR="${LOG_DIR:-/var/log/grok-dogfood}"
OLLAMA_HOST_BIND="127.0.0.1:11434"
# Safe model id charset only (blocks sed/TOML injection via --model).
MODEL_SAFE_RE='^[A-Za-z0-9._:/-]+$'

log() { printf '[grok-gpu-bootstrap] %s\n' "$*"; }
die() { printf '[grok-gpu-bootstrap] ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  sed -n '2,12p' "$0" | sed 's/^# //'
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --license-ok) LICENSE_OK=1; shift ;;
    --model)
      MODEL="${2:-}"
      [[ -n "$MODEL" ]] || die "--model requires a value"
      shift 2
      ;;
    --skip-clone) SKIP_CLONE=1; shift ;;
    -h|--help) usage ;;
    *) die "unknown arg: $1" ;;
  esac
done

if [[ -n "$MODEL" && ! "$MODEL" =~ $MODEL_SAFE_RE ]]; then
  die "invalid --model (allowed: A-Za-z0-9 . _ : / -)"
fi

require_root() {
  [[ "$(id -u)" -eq 0 ]] || die "must run as root"
}

assert_not_symlink() {
  local p
  for p in "$@"; do
    if [[ -L "$p" ]]; then
      die "$p is a symlink — refusing (CWE-367)"
    fi
  done
}

ensure_dogfood_user() {
  if ! id -u "$DOGFOOD_USER" >/dev/null 2>&1; then
    useradd --create-home --shell /bin/bash --system "$DOGFOOD_USER" || \
      useradd --create-home --shell /bin/bash "$DOGFOOD_USER"
  fi
  # No passwordless sudo — agent must not escalate by default.
  if grep -RqsE "^[[:space:]]*${DOGFOOD_USER}[[:space:]].*NOPASSWD" /etc/sudoers /etc/sudoers.d 2>/dev/null; then
    die "passwordless sudo for ${DOGFOOD_USER} is forbidden (Approach A)"
  fi
  mkdir -p "/home/${DOGFOOD_USER}/.grok" "$LOG_DIR" "$WORKSPACE"
  assert_not_symlink "/home/${DOGFOOD_USER}" "/home/${DOGFOOD_USER}/.grok" "$LOG_DIR" "$WORKSPACE"
  chown -R "${DOGFOOD_USER}:${DOGFOOD_USER}" "/home/${DOGFOOD_USER}" "$LOG_DIR"
}

ensure_nvidia() {
  if command -v nvidia-smi >/dev/null 2>&1; then
    log "nvidia-smi present: $(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null || true)"
    return 0
  fi
  log "nvidia-smi missing — installing ubuntu drivers (may take several minutes)"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  # Prefer ubuntu-drivers autoinstall when available; fail loud otherwise.
  if command -v ubuntu-drivers >/dev/null 2>&1; then
    ubuntu-drivers autoinstall || die "ubuntu-drivers autoinstall failed"
  else
    apt-get install -y ubuntu-drivers-common
    ubuntu-drivers autoinstall || die "ubuntu-drivers autoinstall failed after install"
  fi
  command -v nvidia-smi >/dev/null 2>&1 || die "nvidia-smi still missing after driver install — reboot may be required, then re-run"
  log "nvidia after install: $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null || true)"
}

ensure_ollama() {
  # iproute2 provides ss — required for fail-closed public-bind assert.
  if ! command -v ss >/dev/null 2>&1; then
    log "installing iproute2 (ss required for Approach A bind assert)"
    apt-get update -y
    apt-get install -y iproute2 || die "iproute2 install failed — ss required"
  fi
  command -v ss >/dev/null 2>&1 || die "ss required for Approach A loopback exclusivity assert"

  if ! command -v ollama >/dev/null 2>&1; then
    log "installing ollama"
    # Official install path; pin policy is "track stable install.sh" for dogfood T0.
    # <!-- verified: 2026-07-17 source: https://ollama.com/download/linux -->
    curl -fsSL https://ollama.com/install.sh | sh
  fi
  command -v ollama >/dev/null 2>&1 || die "ollama not on PATH after install"

  local drop_dir="/etc/systemd/system/ollama.service.d"
  local drop_file="${drop_dir}/10-loopback.conf"
  mkdir -p "$drop_dir"
  assert_not_symlink "$drop_dir" "$drop_file"
  cat >"$drop_file" <<EOF
[Service]
Environment="OLLAMA_HOST=${OLLAMA_HOST_BIND}"
EOF
  systemctl daemon-reload
  if ! systemctl enable ollama 2>/dev/null; then
    log "WARN: systemctl enable ollama failed (reboot persistence may be missing)"
  fi
  systemctl restart ollama || die "failed to restart ollama"
  # Readiness: poll is-active + loopback health (sleep alone is brittle on cold GPU).
  local _i
  for _i in 1 2 3 4 5 6 7 8 9 10; do
    if systemctl is-active --quiet ollama && curl -fsS --max-time 2 "http://127.0.0.1:11434/api/tags" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
  systemctl is-active --quiet ollama || die "ollama service not active after restart"
}

assert_ollama_loopback() {
  assert_ollama_loopback_listen || die "public or non-loopback Ollama listen on :11434"
  if ! curl -fsS --max-time 5 "http://127.0.0.1:11434/api/tags" >/dev/null; then
    die "curl http://127.0.0.1:11434/api/tags failed — Ollama not healthy on loopback"
  fi
  log "Ollama loopback health OK (OLLAMA_HOST=${OLLAMA_HOST_BIND})"
}

ensure_grok_cli() {
  if command -v grok >/dev/null 2>&1; then
    log "grok already installed: $(grok --version 2>/dev/null || true)"
    return 0
  fi
  log "installing Grok Build CLI"
  curl -fsSL https://x.ai/cli/install.sh | bash || die "grok install.sh failed"
  if [[ -x /root/.grok/bin/grok ]]; then
    install -m 755 /root/.grok/bin/grok /usr/local/bin/grok
  fi
  command -v grok >/dev/null 2>&1 || die "grok not on PATH after install"
  local ver_file="${LOG_DIR}/cli-version.txt"
  assert_not_symlink "$ver_file"
  grok --version 2>/dev/null | tee "$ver_file" || true
  chown "${DOGFOOD_USER}:${DOGFOOD_USER}" "$ver_file" 2>/dev/null || true
}

seed_config_local_open() {
  local cfg="/home/${DOGFOOD_USER}/.grok/config.toml"
  assert_not_symlink "/home/${DOGFOOD_USER}/.grok" "$cfg"
  local model_line='model = "REPLACE_AFTER_LICENSE_PULL"'
  if [[ -n "$MODEL" ]]; then
    model_line="model = \"${MODEL}\""
  fi
  # base_url is fixed in the heredoc — never substituted from env (Approach B guard).
  cat >"$cfg" <<EOF
# Phase 2 open-weight dogfood (#6546). Co-located with Ollama on this host.
# Brand: operator-only — never market as "self-hosted Grok 4.5".
[models]
default = "local-open"

[model.local-open]
${model_line}
base_url = "http://127.0.0.1:11434/v1"
name = "Local open model"
context_window = 128000

# Phase 1 baseline retained for dual-host comparison (API on CX33 uses grok-4.5).
[model.grok-4.5]
# model id filled by operator when using API path; not default on GPU host
EOF
  chown "${DOGFOOD_USER}:${DOGFOOD_USER}" "$cfg"
  chmod 600 "$cfg"
  assert_config_base_url_loopback "$cfg" || die "config base_url must stay loopback"
  grep -qE 'base_url = "http://127\.0\.0\.1:11434/v1"' "$cfg" || die "post-write base_url assert failed"
  log "seeded ${cfg} (default=local-open, base_url=127.0.0.1)"
}

ensure_workspace() {
  if [[ "$SKIP_CLONE" -eq 1 ]]; then
    log "skip clone (--skip-clone)"
    return 0
  fi
  assert_not_symlink "$WORKSPACE"
  if [[ -d "${WORKSPACE}/.git" ]]; then
    log "workspace already present: ${WORKSPACE}"
    return 0
  fi
  log "shallow clone soleur → ${WORKSPACE}"
  sudo -u "$DOGFOOD_USER" git clone --depth 1 https://github.com/jikig-ai/soleur.git "$WORKSPACE" \
    || die "git clone failed"
}

maybe_pull_model() {
  if [[ -z "$MODEL" ]]; then
    log "no --model; skip ollama pull (run with --model ID --license-ok after license memo on #6546)"
    return 0
  fi
  [[ "$LICENSE_OK" -eq 1 ]] || die "refuse ollama pull without --license-ok (record license memo on #6546 first)"
  log "ollama pull ${MODEL}"
  sudo -u "$DOGFOOD_USER" ollama pull "$MODEL" || ollama pull "$MODEL" || die "ollama pull failed"
}

main() {
  require_root
  assert_not_symlink /tmp "$LOG_DIR" /etc/systemd/system/ollama.service.d
  ensure_dogfood_user
  ensure_nvidia
  ensure_ollama
  assert_ollama_loopback
  ensure_grok_cli
  seed_config_local_open
  ensure_workspace
  maybe_pull_model
  assert_ollama_loopback
  local ollama_v grok_v
  ollama_v="$(ollama --version 2>/dev/null || echo unknown)"
  grok_v="$(grok --version 2>/dev/null || echo unknown)"
  log "bootstrap complete: ollama=${ollama_v} grok=${grok_v} bind=${OLLAMA_HOST_BIND} workspace=${WORKSPACE}"
}

main "$@"
