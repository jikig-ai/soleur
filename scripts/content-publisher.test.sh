#!/usr/bin/env bash
# content-publisher.test.sh -- Tempfile-residue harness for scripts/content-publisher.sh (#6734).
#
# NAMING: the legacy unit/integration suite is `test-content-publisher.sh` (older `test-`
# prefix). This file uses the canonical `*.test.sh` suffix and must NOT collide with it;
# both are registered in scripts/test-all.sh.
#
# WHAT IT GUARDS
# --------------
# content-publisher.sh allocates tempfiles via `make_tmp` and cleans up with a single
# `trap … EXIT` over `_TMPFILES`. Every call site uses `f=$(make_tmp)` -- command
# substitution, which runs the function in a SUBSHELL. Appending to `_TMPFILES` from
# INSIDE `make_tmp` mutated the subshell's copy; the parent's array stayed empty and the
# trap expanded to `rm -f ""`, owning nothing. The fix registers in the PARENT scope at
# each of the six call sites.
#
# WHERE THE LEAK ACTUALLY LANDS -- a correction to the issue's framing (#6734)
# ---------------------------------------------------------------------------
# The issue says the trap "removes nothing on every run". The first half is true (the
# trap did own nothing); the conclusion is not. MEASURED: all six call sites `rm -f`
# their own tempfile explicitly on EVERY return path, success and failure alike. So a
# run that completes normally never leaks, with or without the fix.
#
# The trap is a safety net for exactly one window: the span between `mktemp` and that
# explicit `rm -f`. A run that dies inside that window -- signal, or a `set -e` abort on
# an unhandled failure -- is what leaked, and on a long-lived Inngest host (since #4483
# retired scheduled-content-publisher.yml there is no runner teardown) those windows
# accumulate. That is the shape consistent with #6713's 9,470 files / 1.9 GB.
#
# CONSEQUENCE FOR THIS HARNESS: R1 is NOT the discriminator. It passes on broken and
# fixed code alike, because the explicit `rm -f` does the work. It is retained as a
# regression guard against a future refactor that drops that `rm -f` and leans on the
# trap. **R2 is the discriminator** -- it is the only case here that goes RED on the
# unfixed script. Do not read an R1 pass as evidence the trap works.
#
# DEVIATION FROM THE PLAN'S AC1 (">=2-tempfile window") -- recorded, not silently dropped
# ---------------------------------------------------------------------------------------
# AC1 inherited a ">=2 simultaneous tempfiles" requirement from the R0/R1/R2 probe in
# apps/web-platform/infra/workspaces-luks-freeze.test.sh. There, >=2 was load-bearing
# because the defect class was trap REPLACEMENT: with only one file you cannot tell which
# of two traps won. THIS defect class is different -- an EMPTY array -- and a single live
# tempfile separates fixed (0 residue) from broken (1 residue) unambiguously.
#
# More decisively: >=2 is UNREACHABLE in the production shape. All six sites `rm -f`
# before returning, so at most ONE tempfile is live at any instant. Manufacturing a
# second would mean backgrounding an allocator into a subshell -- which is not a shape
# production ever runs, and whose tempfile the parent trap could not own anyway. R3 below
# ASSERTS that ceiling, so the deviation is answered by a measurement rather than a
# comment, and a future reader cannot "restore" AC1 by testing a fictional shape.
#
# Usage: bash scripts/content-publisher.test.sh   (exit 0 all pass, 1 any fail)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/content-publisher.sh"

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); echo "PASS: $1"; }
no() { FAIL=$((FAIL + 1)); echo "FAIL: $1" >&2; }

[[ -f "$TARGET" ]] || { echo "FATAL: $TARGET not found" >&2; exit 1; }

# This harness allocates case directories with `mktemp -d`. Each case removes its own
# directory on the happy path, but a mid-run abort (a failed assertion under `set -e`, a
# signal) would leak them -- the very class this suite exists to guard. One owning trap,
# registered in the PARENT scope, per the rule content-publisher.sh now follows.
_CASE_DIRS=()
trap '((${#_CASE_DIRS[@]} > 0)) && rm -rf "${_CASE_DIRS[@]}"' EXIT

new_case_dir() {
  mktemp -d
}

# The residue probe. R0 proves it can count.
residue_count() { find "$1" -mindepth 1 2>/dev/null | wc -l | tr -d '[:space:]'; }
residue_names() { find "$1" -mindepth 1 -printf '%f ' 2>/dev/null || true; }

# Build a case directory: a content fixture, a stub Bluesky poster, and a child driver.
#
# The child drives the REAL production function `post_bluesky`, not `make_tmp` directly.
# That is load-bearing: after the fix, registration lives at the CALL SITE, so a harness
# that called `make_tmp` raw would observe an unregistered tempfile and report a failure
# that production cannot have. Test the producer, not the helper.
make_case() {
  local root="$1" stub_mode="$2"
  mkdir -p "$root/tmp"

  cat > "$root/content.md" <<'FIXTURE'
---
status: scheduled
publish_date: 2099-01-01
channels: bluesky
title: Residue harness fixture
---

## Bluesky

Residue harness body.
FIXTURE

  # Stub poster. `clean` returns at once; `hold` signals that the tempfile window is
  # OPEN and then blocks, so the parent can abort strictly inside the window.
  if [[ "$stub_mode" == "hold" ]]; then
    cat > "$root/bsky-stub.sh" <<'STUB'
#!/usr/bin/env bash
echo OPEN > "$WINDOW_SIGNAL"
sleep 30
STUB
  else
    cat > "$root/bsky-stub.sh" <<'STUB'
#!/usr/bin/env bash
echo OPEN > "$WINDOW_SIGNAL"
exit 0
STUB
  fi
  chmod +x "$root/bsky-stub.sh"

  cat > "$root/child.sh" <<CHILD
set -euo pipefail
unset DISCORD_WEBHOOK_URL DISCORD_BLOG_WEBHOOK_URL \\
      X_API_KEY X_API_SECRET X_ACCESS_TOKEN X_ACCESS_TOKEN_SECRET \\
      LINKEDIN_ACCESS_TOKEN LINKEDIN_ORG_ACCESS_TOKEN GH_TOKEN || true
# BASH_SOURCE guard in the target means main() does not run on source.
source "$TARGET"
# Redirect the external poster at the stub and satisfy post_bluesky's three guards.
BSKY_SCRIPT="$root/bsky-stub.sh"
BSKY_HANDLE=harness
BSKY_APP_PASSWORD=harness
BSKY_ALLOW_POST=true
export BSKY_HANDLE BSKY_APP_PASSWORD BSKY_ALLOW_POST
post_bluesky "$root/content.md"
CHILD
}

# ---------------------------------------------------------------------------
# R0 -- POSITIVE CONTROL. "0 residue" is evidence only if the counter can count.
# ---------------------------------------------------------------------------
r0=$(new_case_dir)
_CASE_DIRS+=("$r0")
: > "$r0/planted-residue"
r0_seen=$(residue_count "$r0")
if [[ "$r0_seen" == "1" ]]; then
  ok "R0 residue probe positive control: a planted file IS counted (the probe is not blind)"
else
  no "R0 residue probe is BLIND -- planted 1 file, counted '$r0_seen'; R1/R2/R3 prove NOTHING"
fi
rm -rf "$r0"

# ---------------------------------------------------------------------------
# R1 -- a clean run leaves ZERO residue. REGRESSION GUARD, NOT THE DISCRIMINATOR:
# the site's own `rm -f` satisfies this with or without the trap fix.
# ---------------------------------------------------------------------------
r1=$(new_case_dir)
_CASE_DIRS+=("$r1")
make_case "$r1" clean
r1_rc=0
TMPDIR="$r1/tmp" WINDOW_SIGNAL="$r1/window" bash "$r1/child.sh" >/dev/null 2>&1 || r1_rc=$?
if [[ "$r1_rc" != "0" ]]; then
  no "R1 the child did not complete cleanly (rc=$r1_rc) -- not evidence; treat as UN-RUN"
elif [[ ! -f "$r1/window" ]]; then
  no "R1 post_bluesky never reached the allocation point (guards skipped it) -- UN-RUN, not evidence"
else
  r1_res=$(residue_count "$r1/tmp")
  if [[ "$r1_res" == "0" ]]; then
    ok "R1 a clean run through post_bluesky leaves ZERO residue (regression guard on the explicit rm -f)"
  else
    no "R1 a clean run LEAKED $r1_res path(s): $(residue_names "$r1/tmp")"
  fi
fi
rm -rf "$r1"

# ---------------------------------------------------------------------------
# R2 -- THE DISCRIMINATOR. A forced abort strictly inside the live window.
# Unfixed: the trap owns nothing, the tempfile survives. Fixed: the trap removes it.
# ---------------------------------------------------------------------------
r2=$(new_case_dir)
_CASE_DIRS+=("$r2")
make_case "$r2" hold

# setsid: the child gets its own process group, so the abort reaches the blocking stub
# too. Without that, bash defers its EXIT trap until the foreground stub returns and the
# poll below would time out on correctly-fixed code.
TMPDIR="$r2/tmp" WINDOW_SIGNAL="$r2/window" setsid bash "$r2/child.sh" >/dev/null 2>&1 &
r2_pid=$!

# (1) Wait for the window BY STATE -- the stub signals only after post_bluesky has
# allocated. Confirm a tempfile is actually live before aborting.
r2_window=0
for _ in $(seq 1 200); do
  if [[ -f "$r2/window" ]]; then
    shopt -s nullglob; live=("$r2/tmp"/*); shopt -u nullglob
    (( ${#live[@]} >= 1 )) && { r2_window=${#live[@]}; break; }
  fi
  sleep 0.05
done

if (( r2_window == 0 )); then
  no "R2 the tempfile window NEVER opened -- the abort would not be inside it; UN-RUN, not evidence"
  kill -KILL -- "-$r2_pid" 2>/dev/null || true
  wait "$r2_pid" 2>/dev/null || true
else
  # (2) Abort. SIGTERM, not SIGKILL: bash runs the EXIT trap on an untrapped SIGTERM
  # (measured on this host), and the trap firing is the behaviour under test.
  kill -TERM -- "-$r2_pid" 2>/dev/null || true

  # (3) Wait for the trap to have RUN -- state, not elapsed time. The EXIT trap completes
  # before the shell exits, so a reaped child means the trap has finished. Counting
  # before this point would tally an in-flight tempfile and fail correctly-fixed code.
  r2_reaped=0
  for _ in $(seq 1 200); do
    if ! kill -0 "$r2_pid" 2>/dev/null; then r2_reaped=1; break; fi
    sleep 0.05
  done
  # Backstop against a wedged child only -- never the abort path.
  (( r2_reaped == 0 )) && kill -KILL -- "-$r2_pid" 2>/dev/null || true
  wait "$r2_pid" 2>/dev/null || true

  if (( r2_reaped == 0 )); then
    no "R2 the child never reaped after SIGTERM -- the trap did not complete; UN-RUN, not evidence"
  else
    r2_res=$(residue_count "$r2/tmp")
    if [[ "$r2_res" == "0" ]]; then
      ok "R2 a forced abort inside the live tempfile window leaves ZERO residue (the trap owns the allocation)"
    else
      no "R2 abort inside the window LEAKED $r2_res path(s): $(residue_names "$r2/tmp")-- the EXIT trap does not own the tempfile (subshell append)"
    fi
  fi
fi
rm -rf "$r2"

# ---------------------------------------------------------------------------
# R3 -- pin the production ceiling that AC1's ">=2 window" assumed away.
# Asserts every make_tmp call site rm's its own tempfile, which is WHY at most one is
# ever live. If a future edit removes an `rm -f`, this fails and the >=2 question --
# and R1's status as a mere regression guard -- both genuinely reopen.
# ---------------------------------------------------------------------------
alloc_sites=$(grep -cE '^\s*\w+=\$\(make_tmp\)\s*$' "$TARGET" || true)
# Anchor on the `rm -f "$var"` call shape, not the bare variable name: the bare name also
# appears in comments and in `head -c … "$stderr_file"` reads, either of which would let
# this pass vacuously (cq-assert-anchor-not-bare-token).
rm_calls=$(grep -cE '^\s*rm -f "\$(stderr_file|hook_stderr|reply_stderr)"\s*$' "$TARGET" || true)
if (( alloc_sites == 6 )) && (( rm_calls >= alloc_sites )); then
  ok "R3 production ceiling holds: $alloc_sites allocation sites, $rm_calls explicit rm -f calls -- at most ONE tempfile live at a time"
else
  no "R3 production ceiling CHANGED: $alloc_sites allocation sites vs $rm_calls explicit rm -f calls. If a site no longer rm's, the trap became load-bearing on the clean path: re-examine R1 (currently only a regression guard) and AC1's >=2-window question"
fi

echo ""
echo "Total: $((PASS + FAIL))  Pass: $PASS  Fail: $FAIL"
(( FAIL == 0 )) || exit 1
