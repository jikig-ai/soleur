#!/usr/bin/env bash
# SDK-bump sandbox gate — #5875 item 3 / ADR-079.
#
# The #5849 P0 shipped GREEN because a routine @anthropic-ai/claude-agent-sdk bump
# (0.2.85→0.3.197) split bwrap's unshare() and nothing FORCED a human to look. This
# gate closes that class deterministically (no model turn, no creds — ADR-079
# option (b)): it runs BLOCKING in ci.yml's `lockfile-sync` job (a branch-protection
# required check) on every PR.
#
# Two assertions:
#
#   1. PARITY — bun.lock and package-lock.json MUST agree on the resolved version of
#      BOTH @anthropic-ai/claude-agent-sdk AND @anthropic-ai/claude-code. package-lock
#      is deploy-authoritative (the prod image builds via `npm ci` in the Dockerfile,
#      NOT bun.lock which only feeds CI bun test/typecheck), and there is no other
#      cross-parity check, so the two can silently drift. A drift here means the thing
#      CI tests (bun) differs from the thing prod ships (npm) — the exact blind spot
#      that let the gate below be evadable. Kieran P1 correction: key on package-lock,
#      assert bun parity.
#
#   2. BUMP DETECTION + ACK (ADR-079 guardrail 2 — "no silent green on a detected
#      bump"). When either SDK package's resolved version in package-lock.json changes
#      vs the base branch, the merge is GATED until a commit in the branch carries the
#      `sdk-bump-verified:` acknowledgement token. The faithful real-argv validation
#      (drive the bumped SDK's real bwrap argv against the committed seccomp profile)
#      is deferred to a creds-gated follow-up (ADR-079 deferral B); until it is wired,
#      the ack is a REQUIRED maintainer attestation that the committed profile was
#      validated against the new SDK by hand. A silent skip is forbidden (it would
#      re-create #5849's silent-green).
#
# Env overrides (for apps/web-platform/scripts/sdk-bump-sandbox-gate.test.sh — the
# gate is otherwise zero-config against the real repo):
#   SDK_GATE_PKG_LOCK       path to head package-lock.json      (default: apps/web-platform/package-lock.json)
#   SDK_GATE_BUN_LOCK       path to head bun.lock               (default: apps/web-platform/bun.lock)
#   SDK_GATE_BASE_REF       git ref for the merge base          (default: origin/main)
#   SDK_GATE_BASE_PKG_LOCK  path to base package-lock.json      (default: `git show $BASE_REF:...`)
#   SDK_GATE_ACK_TEXT       commit-message text to scan for ack (default: `git log $BASE_REF..HEAD --format=%B`)

set -euo pipefail

PKG_LOCK="${SDK_GATE_PKG_LOCK:-apps/web-platform/package-lock.json}"
BUN_LOCK="${SDK_GATE_BUN_LOCK:-apps/web-platform/bun.lock}"
BASE_REF="${SDK_GATE_BASE_REF:-origin/main}"
ACK_TOKEN="sdk-bump-verified"
FOLLOWUP="the ADR-079 deferral-B follow-up (creds-gated real-argv capture)"

SDK_PACKAGES=("@anthropic-ai/claude-agent-sdk" "@anthropic-ai/claude-code")

# Resolved version from a package-lock.json (npm v3 lockfile: packages map keyed by
# node_modules/<pkg>). Prints "" (never errors) when the package or file is absent.
pkglock_version() { # $1=lockfile $2=pkg
  [[ -f "$1" ]] || { printf ''; return 0; }
  jq -r --arg k "node_modules/$2" '.packages[$k].version // ""' "$1" 2>/dev/null || printf ''
}

# Resolved version from a bun.lock (JSONC — jq cannot parse it). The packages map has
# an entry `"<pkg>": ["<pkg>@<version>", …]`; the leading exact-pkg token carries the
# resolved version. Anchored on the exact `"<pkg>": ["<pkg>@` prefix so the platform
# sub-packages (…-linux-x64@…) never match. Prints "" when absent.
bunlock_version() { # $1=lockfile $2=pkg
  [[ -f "$1" ]] || { printf ''; return 0; }
  local esc; esc="$(printf '%s' "$2" | sed 's/[.[\*^$()+?{|]/\\&/g')"
  grep -oE "\"${esc}\": \[\"${esc}@[^\"]+\"" "$1" 2>/dev/null | head -1 \
    | sed -E "s/.*@([^\"]+)\"$/\1/" || printf ''
}

fail=0

# --- 1. PARITY -------------------------------------------------------------------
for pkg in "${SDK_PACKAGES[@]}"; do
  pv="$(pkglock_version "$PKG_LOCK" "$pkg")"
  bv="$(bunlock_version "$BUN_LOCK" "$pkg")"
  if [[ -z "$pv" ]]; then
    echo "::error::sdk-bump-gate: ${pkg} not found in ${PKG_LOCK} (deploy-authoritative lockfile)."
    fail=1
    continue
  fi
  if [[ -z "$bv" ]]; then
    echo "::error::sdk-bump-gate: ${pkg} not found in ${BUN_LOCK}."
    fail=1
    continue
  fi
  if [[ "$pv" != "$bv" ]]; then
    echo "::error::sdk-bump-gate: LOCKFILE PARITY MISMATCH for ${pkg}: package-lock.json=${pv} (deploy) vs bun.lock=${bv} (CI). The image ships the npm version; a drift means CI tests a different SDK than prod runs. Re-sync both lockfiles (npm ci / bun install) so they agree."
    fail=1
  else
    echo "sdk-bump-gate: parity OK — ${pkg} @ ${pv} (package-lock == bun.lock)."
  fi
done

# --- 2. BUMP DETECTION + ACK -----------------------------------------------------
# Resolve the base package-lock.json (fixture override, else `git show`).
base_pkglock_content() {
  if [[ -n "${SDK_GATE_BASE_PKG_LOCK:-}" ]]; then
    cat "$SDK_GATE_BASE_PKG_LOCK" 2>/dev/null || true
  else
    git show "${BASE_REF}:apps/web-platform/package-lock.json" 2>/dev/null || true
  fi
}

BASE_TMP=""
BASE_CONTENT="$(base_pkglock_content)"
if [[ -n "$BASE_CONTENT" ]]; then
  BASE_TMP="$(mktemp)"
  printf '%s' "$BASE_CONTENT" > "$BASE_TMP"
fi

bumped_pkgs=()
if [[ -n "$BASE_TMP" ]]; then
  for pkg in "${SDK_PACKAGES[@]}"; do
    head_v="$(pkglock_version "$PKG_LOCK" "$pkg")"
    base_v="$(pkglock_version "$BASE_TMP" "$pkg")"
    if [[ -n "$base_v" && -n "$head_v" && "$head_v" != "$base_v" ]]; then
      echo "sdk-bump-gate: DETECTED bump — ${pkg}: ${base_v} → ${head_v}"
      bumped_pkgs+=("$pkg")
    fi
  done
  rm -f "$BASE_TMP"
else
  echo "::warning::sdk-bump-gate: could not resolve the base package-lock.json (ref='${BASE_REF}'); skipping bump-vs-base detection. Parity is still enforced above. (In CI, ensure origin/main is fetched.)"
fi

if [[ "${#bumped_pkgs[@]}" -gt 0 ]]; then
  # Scan branch commit messages for the ack token (fixture override, else git log).
  if [[ -n "${SDK_GATE_ACK_TEXT+x}" ]]; then
    ack_text="${SDK_GATE_ACK_TEXT}"
  else
    ack_text="$(git log "${BASE_REF}..HEAD" --format=%B 2>/dev/null || true)"
  fi
  if printf '%s' "$ack_text" | grep -qiE "\b${ACK_TOKEN}\b"; then
    echo "sdk-bump-gate: SDK bump acknowledged (\`${ACK_TOKEN}\` present) — a maintainer attests the committed seccomp profile was validated against the new SDK. Proceeding."
  else
    echo "::error::sdk-bump-gate: an SDK version bump was detected (${bumped_pkgs[*]}) but NO \`${ACK_TOKEN}:\` acknowledgement is present in the branch commit messages."
    echo "::error::An SDK bump is exactly what caused the #5873 P0 (a split unshare() the seccomp profile did not allow). Until ${FOLLOWUP} lands, a human MUST validate the committed profile (apps/web-platform/infra/seccomp-bwrap.json) against the new SDK's real bwrap argv, then add a commit trailer line: 'sdk-bump-verified: <how it was validated>'."
    fail=1
  fi
fi

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
echo "sdk-bump-gate: OK."
