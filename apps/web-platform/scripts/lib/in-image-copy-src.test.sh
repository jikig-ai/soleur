#!/usr/bin/env bash
# Hermetic tests for in-image-copy-src.sh (#7007).
#
# WHY this suite is the ONLY detector. The exclusions it pins are no-ops on a cold
# CI checkout (no node_modules, no infra/.terraform at the time the in-image
# verifiers run), so no CI job can ever observe a silently-broken exclusion by
# running the real path. Neither ci.yml trigger regex even names the helpers. If
# this suite stops discriminating, the optimisation can revert with no signal
# anywhere.
#
# Pure bash + GNU tar. No docker, no network, no ANTHROPIC_API_KEY. Auto-registered
# by the apps/web-platform/scripts/lib/*.test.sh glob in scripts/test-all.sh
# (want_scripts shard), which CI invokes as `bash scripts/test-all.sh scripts`.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/in-image-copy-src.sh"
H1="$SCRIPT_DIR/../sandbox-canary-verify-in-image.sh"
H2="$SCRIPT_DIR/../plugin-root-propagation-verify-in-image.sh"

T="$(mktemp -d)"
trap 'chmod -R u+rwX "$T" 2>/dev/null || true; rm -rf "$T"' EXIT

PASS=0
FAIL=0
SKIP=0
pass() { echo "  pass: $1"; PASS=$((PASS + 1)); return 0; }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); return 0; }
skip() { echo "  SKIP: $1"; SKIP=$((SKIP + 1)); return 0; }

# Shared path arrays — the single source for assertions 1, 3 and 4 so they cannot
# drift apart. Each carries a minimum-cardinality floor so a builder regression
# fails loud instead of looping zero times (the vacuity class #7001 spent a
# session on).
EXCLUDED_PATHS=(node_modules infra/.terraform infra/sentry/.terraform)
SURVIVE_PATHS=(
  .gitignore .env.example .nvmrc .dockerignore
  .service-role-allowlist .dependency-cruiser.cjs
  package.json package-lock.json scripts/sandbox-canary.mjs
  infra/main.tf infra/.terraform.lock.hcl
  infra/sentry/.terraform.lock.hcl
  test/fixtures/node_modules/keepme.txt
)
EXCLUDED_FLOOR=3
SURVIVE_FLOOR=13

# build_fixture <dir> — every SURVIVE path with distinct non-empty content, plus a
# file inside each EXCLUDED path.
build_fixture() {
  local root="$1" p
  for p in "${SURVIVE_PATHS[@]}"; do
    mkdir -p "$root/$(dirname "$p")"
    printf 'content-for-%s\n' "$p" >"$root/$p"
  done
  for p in "${EXCLUDED_PATHS[@]}"; do
    mkdir -p "$root/$p"
    printf 'must-not-be-copied\n' >"$root/$p/payload.bin"
  done
}

SRC="$T/src"
DST="$T/dst"
build_fixture "$SRC"

# ---------------------------------------------------------------------------
# 1 — positive control (anti-vacuity): the fixture really contains what the
#     absence assertions below claim to prove absent, and both arrays meet their
#     cardinality floors. Without this, assertion 3 passes trivially the day the
#     builder breaks.
# ---------------------------------------------------------------------------
echo "1: positive control — fixture contains every excluded and surviving path"
a1_ok=1
if [ "${#EXCLUDED_PATHS[@]}" -lt "$EXCLUDED_FLOOR" ]; then
  fail "EXCLUDED_PATHS has ${#EXCLUDED_PATHS[@]} entries, floor is $EXCLUDED_FLOOR"
  a1_ok=0
fi
if [ "${#SURVIVE_PATHS[@]}" -lt "$SURVIVE_FLOOR" ]; then
  fail "SURVIVE_PATHS has ${#SURVIVE_PATHS[@]} entries, floor is $SURVIVE_FLOOR"
  a1_ok=0
fi
for p in "${EXCLUDED_PATHS[@]}"; do
  [ -e "$SRC/$p/payload.bin" ] || { fail "fixture missing excluded fixture file $p/payload.bin"; a1_ok=0; }
done
for p in "${SURVIVE_PATHS[@]}"; do
  [ -s "$SRC/$p" ] || { fail "fixture missing or empty survivor $p"; a1_ok=0; }
done
[ "$a1_ok" -eq 1 ] && pass "fixture positive control (${#EXCLUDED_PATHS[@]} excluded, ${#SURVIVE_PATHS[@]} survivors)"

# ---------------------------------------------------------------------------
# 2 — run the REAL shipped artifact. No marker extraction, no substitution, no
#     eval: the test invokes the file that ships.
# ---------------------------------------------------------------------------
echo "2: real artifact runs clean"
set +e
a2_out="$(bash "$SUT" "$SRC" "$DST" 2>&1)"
a2_rc=$?
set -e
if [ "$a2_rc" -eq 0 ]; then
  pass "bash in-image-copy-src.sh SRC DST exited 0"
  A2_OK=1
else
  fail "exit $a2_rc; output: $a2_out"
  A2_OK=0
fi

# ---------------------------------------------------------------------------
# 3 — every excluded path is absent from DEST.
#     SKIP (not pass) when 2 failed: an empty DEST satisfies every absence check,
#     and reporting "pass" in that state actively misleads.
# ---------------------------------------------------------------------------
echo "3: excluded paths absent from DEST"
if [ "$A2_OK" -ne 1 ]; then
  skip "assertion 2 failed — absence checks would be vacuous against an empty DEST"
else
  a3_ok=1
  for p in "${EXCLUDED_PATHS[@]}"; do
    if [ -e "$DST/$p" ]; then
      fail "excluded path was copied: $p"
      a3_ok=0
    fi
  done
  [ "$a3_ok" -eq 1 ] && pass "all ${#EXCLUDED_PATHS[@]} excluded paths absent"
fi

# ---------------------------------------------------------------------------
# 4 — whole-tree parity + per-survivor CONTENT.
#     cmp, not `test -e`: truncation is the headline failure mode and a 0-byte
#     survivor passes an existence check. The diff --exclude flags mask basename
#     matches at ANY depth on both sides, which is exactly why
#     test/fixtures/node_modules/keepme.txt must be cmp'd explicitly.
# ---------------------------------------------------------------------------
echo "4: whole-tree parity and survivor content"
if [ "$A2_OK" -ne 1 ]; then
  skip "assertion 2 failed — parity would compare against an empty DEST"
else
  a4_ok=1
  set +e
  diff_out="$(diff -rq --exclude=node_modules --exclude=.terraform "$SRC" "$DST" 2>&1)"
  diff_rc=$?
  set -e
  if [ "$diff_rc" -ne 0 ]; then
    fail "whole-tree diff reported differences: $diff_out"
    a4_ok=0
  fi
  for p in "${SURVIVE_PATHS[@]}"; do
    if ! cmp -s "$SRC/$p" "$DST/$p"; then
      fail "survivor missing or content differs: $p"
      a4_ok=0
    fi
  done
  [ "$a4_ok" -eq 1 ] && pass "tree parity clean and all ${#SURVIVE_PATHS[@]} survivors byte-identical"
fi

# ---------------------------------------------------------------------------
# 5 — producer-failure control (the DISCRIMINATING stimulus).
#     An UNREADABLE MEMBER gives PIPESTATUS=(2 0): with pipefail the guard fires
#     (exit 2), without it the shell exits 0 and DEST is silently truncated while
#     npm ci carries on against a partial tree. A MISSING source fails BOTH tars
#     and returns non-zero with or without pipefail, so it does not discriminate
#     and must not be used here.
#     Root reads anything, so this control is vacuous as root — loud SKIP instead.
# ---------------------------------------------------------------------------
echo "5: producer-failure control — unreadable member must FATAL, not truncate"
if [ "$(id -u)" -eq 0 ]; then
  skip "running as root: an unreadable member is readable, so this control cannot discriminate"
else
  SRC5="$T/src5"
  DST5="$T/dst5"
  build_fixture "$SRC5"
  printf 'unreadable\n' >"$SRC5/secret.bin"
  chmod 000 "$SRC5/secret.bin"
  set +e
  a5_err="$(bash "$SUT" "$SRC5" "$DST5" 2>&1 >/dev/null)"
  a5_rc=$?
  set -e
  if [ "$a5_rc" -eq 0 ]; then
    fail "unreadable member produced exit 0 — DEST is silently truncated"
  elif ! grep -q 'FATAL:' <<<"$a5_err"; then
    fail "non-zero exit ($a5_rc) but no FATAL: diagnostic on stderr; got: $a5_err"
  else
    pass "unreadable member → exit $a5_rc + FATAL: on stderr"
  fi
fi

# ---------------------------------------------------------------------------
# 6 — both call sites migrated, anchored on the INVOCATION.
#     A bare in-image-copy-src.sh grep is vacuous by construction here: each
#     helper's header sentence names the file, so the positive half would pass
#     with the call site deleted (cq-assert-anchor-not-bare-token).
# ---------------------------------------------------------------------------
echo "6: both helpers call the shared copy and no longer use cp"
CALL_LITERAL='bash /src/scripts/lib/in-image-copy-src.sh /src /build'
a6_ok=1
for h in "$H1" "$H2"; do
  hname="$(basename "$h")"
  if ! grep -qF -- "$CALL_LITERAL" "$h"; then
    fail "$hname does not invoke the shared copy ($CALL_LITERAL)"
    a6_ok=0
  fi
  if grep -qE '^[[:space:]]*cp -[aRrP]' "$h"; then
    fail "$hname still contains a cp recursive copy"
    a6_ok=0
  fi
done
[ "$a6_ok" -eq 1 ] && pass "both helpers migrated to the shared copy"

# ---------------------------------------------------------------------------
# 7 — bash -n over both helpers and the copy script. An unbalanced quote inside a
#     helper's single-quoted `docker run … bash -c '…'` body breaks the OUTER
#     parse, so one builtin covers the whole apostrophe class.
# ---------------------------------------------------------------------------
echo "7: bash -n parses all three scripts"
a7_ok=1
for f in "$H1" "$H2" "$SUT"; do
  set +e
  n_out="$(bash -n "$f" 2>&1)"
  n_rc=$?
  set -e
  if [ "$n_rc" -ne 0 ]; then
    fail "bash -n failed on $(basename "$f"): $n_out"
    a7_ok=0
  fi
done
[ "$a7_ok" -eq 1 ] && pass "bash -n clean on both helpers and the copy script"

# ---------------------------------------------------------------------------
# 8 — base-image digest parity. Both helper headers already say "keep in sync on
#     a base bump"; nothing enforced it. This reddens a one-sided bump.
# ---------------------------------------------------------------------------
echo "8: both helpers pin the same base-image digest"
d1="$(grep -oE 'node:22-slim@sha256:[0-9a-f]{64}' "$H1" | head -1 || true)"
d2="$(grep -oE 'node:22-slim@sha256:[0-9a-f]{64}' "$H2" | head -1 || true)"
if [ -z "$d1" ] || [ -z "$d2" ]; then
  fail "could not extract a pinned digest from both helpers (h1='$d1' h2='$d2')"
elif [ "$d1" != "$d2" ]; then
  fail "digest drift: $(basename "$H1")=$d1 vs $(basename "$H2")=$d2"
else
  pass "both helpers pin $d1"
fi

echo
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ] || exit 1
