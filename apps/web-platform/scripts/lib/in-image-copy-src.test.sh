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
#
# NOT pinned here: --no-same-owner. As non-root, tar cannot chown at all, so this
# suite is structurally unable to discriminate its presence. It is proven by the
# in-image rehearsal in the PR body instead. Do not read a green run as covering it.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/in-image-copy-src.sh"
H1="$SCRIPT_DIR/../sandbox-canary-verify-in-image.sh"
H2="$SCRIPT_DIR/../plugin-root-propagation-verify-in-image.sh"
DOCKERFILE="$SCRIPT_DIR/../../Dockerfile"

# Derived, never restated: the in-container invocation must follow the SUT's real
# location under apps/web-platform. A hardcoded literal here would let the file move
# while the helpers and this suite stayed mutually consistent and green.
SUT_REL="${SUT#*/apps/web-platform/}"
CALL_LITERAL="bash /src/$SUT_REL /src /build"

T="$(mktemp -d)"
trap 'chmod -R u+rwX "$T" 2>/dev/null || true; rm -rf "$T"' EXIT

PASS=0
FAIL=0
SKIP=0
pass() { echo "  pass: $1"; PASS=$((PASS + 1)); return 0; }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); return 0; }
skip() { echo "  SKIP: $1"; SKIP=$((SKIP + 1)); return 0; }

# Outermost anti-vacuity guard. Every control below lives INSIDE an assertion block,
# so deleting the blocks silences all of them at once while the suite still exits 0
# (measured: removing every block yields "0 passed, 0 failed", exit 0). A FLOOR, not
# equality -- a future 11th assertion must not red. SKIP counts, so the root path
# degrades observably instead of silently.
MIN_ASSERTIONS=10

# Shared path arrays -- the single source for assertions 1, 3 and 4 so they cannot
# drift apart. Cardinality floors catch a builder regression; the MEMBERSHIP list
# below catches the subtler case where a sentinel is swapped out for an ordinary file
# and the count still satisfies the floor.
EXCLUDED_PATHS=(node_modules .next out infra/.terraform infra/sentry/.terraform)
SURVIVE_PATHS=(
  .gitignore .env.example .nvmrc .dockerignore
  .service-role-allowlist .dependency-cruiser.cjs
  .github/keep.txt
  package.json package-lock.json scripts/sandbox-canary.mjs
  infra/main.tf infra/.terraform.lock.hcl
  infra/sentry/.terraform.lock.hcl
  test/fixtures/node_modules/keepme.txt
  test/fixtures/deep/nested/node_modules/deeper.txt
  test/fixtures/nested/.next/keep.txt
  test/fixtures/nested/out/keep.txt
)
EXCLUDED_FLOOR=5
SURVIVE_FLOOR=17
# These specific survivors are the ONLY things that detect an over-aggressive
# exclusion (a root-anchor dropped from ./node_modules, or .terraform gaining a
# wildcard). A cardinality floor alone lets them be swapped for ordinary files.
REQUIRED_SURVIVORS=(
  test/fixtures/node_modules/keepme.txt
  test/fixtures/deep/nested/node_modules/deeper.txt
  infra/.terraform.lock.hcl
  infra/sentry/.terraform.lock.hcl
  test/fixtures/nested/.next/keep.txt
  test/fixtures/nested/out/keep.txt
)

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
  # Pins tar's NON-dereferencing behaviour. If someone adds -h/--dereference "for
  # fidelity", link targets from OUTSIDE the read-only mount would be pulled into
  # DEST; assertion 4 would still pass on content, so only the -L check catches it.
  ln -sfn package.json "$root/link-to-package.json"
}

SRC="$T/src"
DST="$T/dst"
build_fixture "$SRC"

# ---------------------------------------------------------------------------
# 1 — positive control: the fixture really contains what the absence assertions
#     claim to prove absent, the arrays meet their floors, AND the over-reach
#     sentinels are actually present by name.
# ---------------------------------------------------------------------------
echo "1: positive control — fixture, cardinality floors, sentinel membership"
a1_ok=1
[ "${#EXCLUDED_PATHS[@]}" -ge "$EXCLUDED_FLOOR" ] || { fail "EXCLUDED_PATHS ${#EXCLUDED_PATHS[@]} < floor $EXCLUDED_FLOOR"; a1_ok=0; }
[ "${#SURVIVE_PATHS[@]}" -ge "$SURVIVE_FLOOR" ] || { fail "SURVIVE_PATHS ${#SURVIVE_PATHS[@]} < floor $SURVIVE_FLOOR"; a1_ok=0; }
for p in "${EXCLUDED_PATHS[@]}"; do
  [ -e "$SRC/$p/payload.bin" ] || { fail "fixture missing excluded file $p/payload.bin"; a1_ok=0; }
done
for p in "${SURVIVE_PATHS[@]}"; do
  [ -s "$SRC/$p" ] || { fail "fixture missing or empty survivor $p"; a1_ok=0; }
done
for req in "${REQUIRED_SURVIVORS[@]}"; do
  found=0
  for p in "${SURVIVE_PATHS[@]}"; do [ "$p" = "$req" ] && found=1; done
  [ "$found" -eq 1 ] || { fail "over-reach sentinel dropped from SURVIVE_PATHS: $req"; a1_ok=0; }
done
[ -L "$SRC/link-to-package.json" ] || { fail "fixture symlink missing"; a1_ok=0; }
[ "$a1_ok" -eq 1 ] && pass "fixture control (${#EXCLUDED_PATHS[@]} excluded, ${#SURVIVE_PATHS[@]} survivors, ${#REQUIRED_SURVIVORS[@]} sentinels)"

# ---------------------------------------------------------------------------
# 2 — run the REAL shipped artifact.
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
# 3 — every excluded path absent. SKIP (not pass) when 2 failed: an empty DEST
#     satisfies every absence check.
# ---------------------------------------------------------------------------
echo "3: excluded paths absent from DEST"
if [ "$A2_OK" -ne 1 ]; then
  skip "assertion 2 failed — absence checks would be vacuous against an empty DEST"
else
  a3_ok=1
  for p in "${EXCLUDED_PATHS[@]}"; do
    [ -e "$DST/$p" ] && { fail "excluded path was copied: $p"; a3_ok=0; }
  done
  [ "$a3_ok" -eq 1 ] && pass "all ${#EXCLUDED_PATHS[@]} excluded paths absent"
fi

# ---------------------------------------------------------------------------
# 4 — whole-tree parity + per-survivor CONTENT + symlink preservation.
#     cmp, not `test -e`: truncation is the headline failure mode. The diff
#     --exclude flags mask basenames at ANY depth on BOTH sides, which is exactly
#     why the nested node_modules survivors must be cmp'd explicitly.
# ---------------------------------------------------------------------------
echo "4: whole-tree parity, survivor content, symlink preserved"
if [ "$A2_OK" -ne 1 ]; then
  skip "assertion 2 failed — parity would compare against an empty DEST"
else
  a4_ok=1
  set +e
  diff_out="$(diff -rq --exclude=node_modules --exclude=.terraform --exclude=.next --exclude=out "$SRC" "$DST" 2>&1)"
  diff_rc=$?
  set -e
  [ "$diff_rc" -ne 0 ] && { fail "whole-tree diff differs: $diff_out"; a4_ok=0; }
  for p in "${SURVIVE_PATHS[@]}"; do
    cmp -s "$SRC/$p" "$DST/$p" || { fail "survivor missing or content differs: $p"; a4_ok=0; }
  done
  [ -L "$DST/link-to-package.json" ] || { fail "symlink was dereferenced or dropped (tar -h added?)"; a4_ok=0; }
  [ "$a4_ok" -eq 1 ] && pass "parity clean, ${#SURVIVE_PATHS[@]} survivors byte-identical, symlink preserved"
fi

# ---------------------------------------------------------------------------
# 5 — tar status CLASSIFICATION, via a stubbed tar. Deterministic and root-blind.
#     GNU tar overloads its status: 2 = error (refuse), 1 = warning (proceed).
#     The real unreadable-member case (assertion 6) cannot run as root, which is
#     how this ships -- so the classification itself needs a root-independent test.
#     Only `tar` is faked; the script under test is the real shipped artifact.
# ---------------------------------------------------------------------------
echo "5: tar status classification (2=FATAL, 1=WARN, consumer failure=FATAL)"
STUB="$T/stub"
mkdir -p "$STUB"
cat >"$STUB/tar" <<'STUBEOF'
#!/usr/bin/env bash
for a in "$@"; do
  case "$a" in
    -cf) printf 'fake-archive-bytes\n'; exit "${FAKE_TAR_PRODUCER_RC:-0}" ;;
    -xf) cat >/dev/null 2>&1; exit "${FAKE_TAR_CONSUMER_RC:-0}" ;;
  esac
done
exit 0
STUBEOF
chmod +x "$STUB/tar"

run_stubbed() { # $1=producer_rc $2=consumer_rc -> prints "rc|stderr"
  local out rc
  set +e
  out="$(PATH="$STUB:$PATH" FAKE_TAR_PRODUCER_RC="$1" FAKE_TAR_CONSUMER_RC="$2" \
    bash "$SUT" "$SRC" "$T/stubdst$1$2" 2>&1 >/dev/null)"
  rc=$?
  set -e
  printf '%s|%s' "$rc" "$out"
}

a5_ok=1
r="$(run_stubbed 2 0)"
case "$r" in
  1\|*FATAL:*) ;;
  *) fail "producer status 2 must FATAL+exit1, got: $r"; a5_ok=0 ;;
esac
r="$(run_stubbed 1 0)"
case "$r" in
  0\|*WARN:*) [[ "$r" == *FATAL:* ]] && { fail "producer status 1 must WARN, not FATAL: $r"; a5_ok=0; } ;;
  *) fail "producer status 1 must WARN+exit0 (copy is complete), got: $r"; a5_ok=0 ;;
esac
r="$(run_stubbed 0 2)"
case "$r" in
  1\|*FATAL:*) ;;
  *) fail "consumer failure must FATAL+exit1, got: $r"; a5_ok=0 ;;
esac
r="$(run_stubbed 0 0)"
case "$r" in
  0\|*) [[ "$r" == *FATAL:* || "$r" == *WARN:* ]] && { fail "clean run must be silent, got: $r"; a5_ok=0; } ;;
esac
[ "$a5_ok" -eq 1 ] && pass "status 2→FATAL/exit1, 1→WARN/exit0, consumer-fail→FATAL/exit1, clean→silent"

# ---------------------------------------------------------------------------
# 6 — real producer-failure control (unreadable member). Complements assertion 5
#     by exercising the genuine tar rather than a stub. Root reads anything, so
#     this SKIPs as root -- assertion 5 is the root-safe half.
# ---------------------------------------------------------------------------
echo "6: real unreadable member must FATAL, not truncate"
if [ "$(id -u)" -eq 0 ]; then
  skip "running as root: an unreadable member is readable, so this cannot discriminate (assertion 5 covers the classification)"
else
  SRC6="$T/src6"
  build_fixture "$SRC6"
  printf 'unreadable\n' >"$SRC6/secret.bin"
  chmod 000 "$SRC6/secret.bin"
  set +e
  a6_err="$(bash "$SUT" "$SRC6" "$T/dst6" 2>&1 >/dev/null)"
  a6_rc=$?
  set -e
  if [ "$a6_rc" -eq 0 ]; then
    fail "unreadable member produced exit 0 — DEST is silently truncated"
  elif ! grep -q 'FATAL:' <<<"$a6_err"; then
    fail "non-zero exit ($a6_rc) but no FATAL: on stderr; got: $a6_err"
  else
    pass "unreadable member → exit $a6_rc + FATAL: on stderr"
  fi
fi

# ---------------------------------------------------------------------------
# 7 — both call sites migrated. COMMENT-BLIND: the SUT's own header carries the
#     invocation literal as usage text, so a bare file-wide grep is satisfied by a
#     decoy comment while the real call site is replaced by `cp -r` (measured: a
#     full revert of the optimisation passed 8/8 before this was comment-blind).
#     The ban is on the exec stream touching /src with any copy verb, not on a
#     line-initial `cp -[aRrP]` (which `cp -vr` and `cp --recursive` walk past).
# ---------------------------------------------------------------------------
echo "7: both helpers call the shared copy; no raw copy verb touches /src"
a7_ok=1
for h in "$H1" "$H2"; do
  hname="$(basename "$h")"
  body="$(grep -vE '^[[:space:]]*#' "$h")"
  grep -qF -- "$CALL_LITERAL" <<<"$body" \
    || { fail "$hname does not invoke the shared copy in executable code ($CALL_LITERAL) — it must be EXECUTED, not sourced: sourcing leaks pipefail into the caller's bun-install pipeline"; a7_ok=0; }
  grep -qE '\b(cp|rsync)\b[^|]*/src' <<<"$body" \
    && { fail "$hname copies /src with a raw copy verb outside the shared helper"; a7_ok=0; }
done
[ "$a7_ok" -eq 1 ] && pass "both helpers migrated (comment-blind), no raw copy verb on /src"

# ---------------------------------------------------------------------------
# 8 — bash -n over all three. An unbalanced quote inside a helper's single-quoted
#     `docker run … bash -c '…'` body breaks the OUTER parse.
# ---------------------------------------------------------------------------
echo "8: bash -n parses all three scripts"
a8_ok=1
for f in "$H1" "$H2" "$SUT"; do
  set +e
  n_out="$(bash -n "$f" 2>&1)"
  n_rc=$?
  set -e
  [ "$n_rc" -ne 0 ] && { fail "bash -n failed on $(basename "$f"): $n_out"; a8_ok=0; }
done
[ "$a8_ok" -eq 1 ] && pass "bash -n clean on both helpers and the copy script"

# ---------------------------------------------------------------------------
# 9 — base-image digest parity against the LEADER. Both helper headers say "pin to
#     the same base as apps/web-platform/Dockerfile", and Renovate's dockerfile
#     manager bumps the Dockerfile digest and AUTOMERGES (renovate.json5:
#     default:automergeDigest + platformAutomerge). The helpers are outside every
#     configured manager, so a helper-vs-helper check stays green while BOTH go
#     stale against the image actually deployed — silently breaking ADR-079's
#     capture-env == replay-env == deploy-image invariant.
#     Anchored on the pin site (FROM / IMG=), and each helper must carry EXACTLY
#     one digest: a second occurrence in a comment would otherwise let the real
#     pin be removed while the guard passed.
# ---------------------------------------------------------------------------
echo "9: digest parity — Dockerfile (leader) and both helper pins agree"
a9_ok=1
digests=""
df_n="$(grep -cE '^FROM node:22-slim@sha256:[0-9a-f]{64}' "$DOCKERFILE" || true)"
if [ "$df_n" -lt 1 ]; then
  fail "no pinned FROM node:22-slim@sha256 in $(basename "$DOCKERFILE")"
  a9_ok=0
else
  digests="$(grep -oE '^FROM node:22-slim@sha256:[0-9a-f]{64}' "$DOCKERFILE" | sed 's/^FROM //')"
fi
for h in "$H1" "$H2"; do
  hname="$(basename "$h")"
  n="$(grep -cE 'node:22-slim@sha256:[0-9a-f]{64}' "$h" || true)"
  if [ "$n" -ne 1 ]; then
    fail "$hname carries $n pinned digests, expected exactly 1 (a decoy in a comment would unpin the real one)"
    a9_ok=0
    continue
  fi
  d="$(grep -E '^IMG=' "$h" | grep -oE 'node:22-slim@sha256:[0-9a-f]{64}' || true)"
  if [ -z "$d" ]; then
    fail "$hname has a digest but not on its IMG= pin line — the docker run image is unpinned"
    a9_ok=0
    continue
  fi
  digests="$digests
$d"
done
if [ "$a9_ok" -eq 1 ]; then
  uniq_n="$(printf '%s\n' "$digests" | grep -v '^$' | sort -u | wc -l)"
  if [ "$uniq_n" -ne 1 ]; then
    fail "digest drift across Dockerfile + helpers ($uniq_n distinct): $(printf '%s' "$digests" | tr '\n' ' ')"
  else
    pass "Dockerfile and both helpers pin $(printf '%s\n' "$digests" | grep -v '^$' | sort -u)"
  fi
fi

# ---------------------------------------------------------------------------
# 10 — the /src contract. Both helpers document that $APP_DIR must carry the copy
#      tool; nothing asserted it. Mounting $PWD instead of $PWD/$APP_DIR leaves
#      every other assertion green while the container dies on a missing file.
# ---------------------------------------------------------------------------
echo "10: helpers mount \$APP_DIR (not \$PWD) as /src"
a10_ok=1
for h in "$H1" "$H2"; do
  hname="$(basename "$h")"
  body="$(grep -vE '^[[:space:]]*#' "$h")"
  # shellcheck disable=SC2016  # the literal string is the assertion; no expansion wanted
  grep -qF -- '$PWD/$APP_DIR:/src:ro' <<<"$body" \
    || { fail "$hname does not mount \$PWD/\$APP_DIR at /src — $SUT_REL would be unreachable in-container"; a10_ok=0; }
done
[ "$a10_ok" -eq 1 ] && pass "both helpers mount \$PWD/\$APP_DIR:/src:ro"

echo
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
RAN=$((PASS + FAIL + SKIP))
if [ "$RAN" -lt "$MIN_ASSERTIONS" ]; then
  echo "FATAL: only $RAN assertions ran, floor is $MIN_ASSERTIONS — assertions were deleted or silently skipped" >&2
  exit 1
fi
[ "$FAIL" -eq 0 ] || exit 1
