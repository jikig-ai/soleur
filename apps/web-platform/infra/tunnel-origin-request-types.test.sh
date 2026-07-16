#!/usr/bin/env bash
# Pins tunnel.tf's origin_request values to the PINNED cloudflare provider's schema types (#6511).
#
# WHY: `connect_timeout = 5` sat in tunnel.tf from #6357 until #6511 and NEVER took effect. The
# v4 provider schema is `connect_timeout: string` (a Go duration). A bare `5` coerces to "5",
# fails Cloudflare's duration parse, and lands as "0s" — so every apply planned
# `connect_timeout = "0s" -> "5"`, applied it, reported success, and read back "0s" forever. The
# mitigation for the 2026-07-11 502 (#6357) was inert the whole time, and the perpetual `1 to
# change` trained everyone to read apply output as noise.
#
# The old comment asserted `INTEGER seconds (NOT "5s")` — exactly backwards. That IS the v5 shape;
# this repo pins `~> 4.0`. Copying v5/REST-API docs onto a v4 pin is the trap; this test is the
# tripwire for it.
#
# HERMETIC: pure text assertions over the HCL. No terraform, no network, no provider download —
# it runs in the same ungated job as its siblings. It therefore pins the KNOWN-correct shape
# rather than re-deriving the schema; see the provider-version guard below, which fails loudly if
# the pin moves to a major where the correct shape differs.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF="$DIR/tunnel.tf"
MAIN="$DIR/main.tf"
[[ -r "$TF" ]]   || { echo "FAIL: cannot read $TF" >&2; exit 1; }
[[ -r "$MAIN" ]] || { echo "FAIL: cannot read $MAIN" >&2; exit 1; }

pass=0; fail=0
assert() { # <name> <cmd>
  if eval "$2" >/dev/null 2>&1; then printf '  PASS: %s\n' "$1"; pass=$((pass+1))
  else printf '  FAIL: %s\n' "$1" >&2; fail=$((fail+1)); fi
}

echo "--- #6511: origin_request values match the v4 provider's schema types ---"

# The load-bearing one. v4 schema: connect_timeout is a STRING Go duration.
assert "connect_timeout is a quoted duration string with a unit (not a bare integer)" \
  "grep -qE '^[[:space:]]*connect_timeout[[:space:]]*=[[:space:]]*\"[0-9]+(ns|us|ms|s|m|h)\"' '$TF'"

# The specific regression: a bare number silently becomes 0s on the origin.
assert "connect_timeout is NOT assigned a bare number (coerces to \"5\" -> parses as 0s)" \
  "! grep -qE '^[[:space:]]*connect_timeout[[:space:]]*=[[:space:]]*[0-9]+[[:space:]]*(#.*)?$' '$TF'"

# The #6357 mitigation's actual value. If someone retunes it, this fails and they must confirm
# the new bound is deliberate — the whole point is that it was silently 0s for weeks.
# Whitespace-tolerant on purpose: a future `terraform fmt` may realign this block if a longer
# sibling key joins origin_request, and the value would still be correct — don't red on alignment.
assert "connect_timeout is 5s (the #6357 fail-fast bound on the registry origin)" \
  "grep -qE '^[[:space:]]*connect_timeout[[:space:]]*=[[:space:]]*\"5s\"' '$TF'"

# Booleans stay booleans — no_happy_eyeballs is `bool` in the same schema block and was always
# correct. Pinned so a future 'fix everything to strings' sweep doesn't over-correct it.
assert "no_happy_eyeballs is a bare bool (schema: bool), not quoted" \
  "grep -qE '^[[:space:]]*no_happy_eyeballs[[:space:]]*=[[:space:]]*(true|false)[[:space:]]*(#.*)?$' '$TF'"

# The assertions above encode V4 semantics. In v5 connect_timeout became an INTEGER, so if the pin
# ever moves to ~> 5.0 these tests would enforce a shape the provider rejects. Fail loudly here
# rather than let the next person "fix" the tests to match a provider they didn't check.
echo "--- provider pin guard (these assertions are v4-specific) ---"
assert "cloudflare provider is still pinned to v4 (connect_timeout=string; v5 makes it an integer)" \
  "grep -A2 'cloudflare = {' '$MAIN' | grep -qE 'version[[:space:]]*=[[:space:]]*\"~> 4\.[0-9]+\"'"

printf '\n=== %s: %d passed, %d failed ===\n' "$(basename "$0")" "$pass" "$fail"
[[ "$fail" -eq 0 ]]
