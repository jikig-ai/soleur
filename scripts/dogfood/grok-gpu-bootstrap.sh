#!/usr/bin/env bash
# #6546 — Thin idempotent bootstrap for Phase 2 open-weight dogfood on Hetzner Robot GEX44.
# Approach A: Grok CLI + Ollama co-located; Ollama bound to loopback only.
#
# Usage (as root on the GEX host):
#   bash grok-gpu-bootstrap.sh
#   bash grok-gpu-bootstrap.sh --model qwen2.5-coder:32b --license-ok
#
# Does NOT order hardware. Does NOT pull a model without --license-ok.
# <!-- verified: 2026-07-17 source: https://docs.ollama.com/api/openai-compatibility OLLAMA_HOST pattern -->
set -euo pipefail

LICENSE_OK=0
MODEL=""
SKIP_CLONE=0
DOGFOOD_USER="${DOGFOOD_USER:-dogfood}"
WORKSPACE="${WORKSPACE:-/home/${DOGFOOD_USER}/soleur}"
LOG_DIR="${LOG_DIR:-/var/log/grok-dogfood}"
OLLAMA_HOST_BIND="127.0.0.1:11434"

log() { printf '[grok-gpu-bootstrap] %s\n' "$*"; }
die() { printf '[grok-gpu-bootstrap] ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  sed -n '2,12p' "$0" | sed 's/^# //'
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --license-ok) LICENSE_OK=1; shift ;;
    --model) MODEL="${2:-}"; shift 2 ;;
    --skip-clone) SKIP_CLONE=1; shift ;;
    -h|--help) usage ;;
    *) die "unknown arg: $1" ;;
  esac
done

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
  mkdir -p "/home/${DOGFOOD_USER}/.grok" "$LOG_DIR" "$WORKSPACE"
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
  if ! command -v ollama >/dev/null 2>&1; then
    log "installing ollama"
    # Official install path; pin policy is "track stable install.sh" for dogfood T0.
    # <!-- verified: 2026-07-17 source: https://ollama.com/download/linux -->
    curl -fsSL https://ollama.com/install.sh | sh
  fi
  command -v ollama >/dev/null 2>&1 || die "ollama not on PATH after install"

  mkdir -p /etc/systemd/system/ollama.service.d
  cat >/etc/systemd/system/ollama.service.d/10-loopback.conf <<EOF
[Service]
Environment="OLLAMA_HOST=${OLLAMA_HOST_BIND}"
EOF
  systemctl daemon-reload
  systemctl enable ollama 2>/dev/null || true
  systemctl restart ollama || die "failed to restart ollama"
  sleep 2
  systemctl is-active --quiet ollama || die "ollama service not active"
}

assert_ollama_loopback() {
  # Fail if something is listening on all interfaces for 11434.
  if command -v ss >/dev/null 2>&1; then
    if ss -lnt 2>/dev/null | grep -E '[:.]11434\b' | grep -qE '0\.0\.0\.0:11434|\*:11434|\[::\]:11434'; then
      die "Ollama appears bound to a public interface (0.0.0.0/:: on :11434) — Approach A requires loopback only"
    fi
  fi
  # Positive health on loopback.
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
  grok --version 2>/dev/null | tee "${LOG_DIR}/cli-version.txt" || true
  chown "${DOGFOOD_USER}:${DOGFOOD_USER}" "${LOG_DIR}/cli-version.txt" 2>/dev/null || true
}

seed_config_local_open() {
  local cfg="/home/${DOGFOOD_USER}/.grok/config.toml"
  # base_url must stay loopback — never a public GEX IP (Approach B forbidden).
  cat >"$cfg" <<'EOF'
# Phase 2 open-weight dogfood (#6546). Co-located with Ollama on this host.
# Brand: operator-only — never market as "self-hosted Grok 4.5".
[models]
default = "local-open"

[model.local-open]
model = "REPLACE_AFTER_LICENSE_PULL"
base_url = "http://127.0.0.1:11434/v1"
name = "Local open model"
context_window = 128000

# Phase 1 baseline retained for dual-host comparison (API on CX33 uses grok-4.5).
[model.grok-4.5]
# model id filled by operator when using API path; not default on GPU host
EOF
  if [[ -n "$MODEL" ]]; then
    # shellcheck disable=SC2016
    sed -i "s|model = \"REPLACE_AFTER_LICENSE_PULL\"|model = \"${MODEL}\"|" "$cfg"
  fi
  chown "${DOGFOOD_USER}:${DOGFOOD_USER}" "$cfg"
  chmod 644 "$cfg"
  log "seeded ${cfg} (default=local-open, base_url=127.0.0.1)"
}

ensure_workspace() {
  if [[ "$SKIP_CLONE" -eq 1 ]]; then
    log "skip clone (--skip-clone)"
    return 0
  fi
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
