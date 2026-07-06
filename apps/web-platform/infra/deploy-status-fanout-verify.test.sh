#!/usr/bin/env bash
# Network-free unit tests for the shared off-host web-2 acceptance verify
# (apps/web-platform/infra/scripts/deploy-status-fanout-verify.sh).
#
# #6051: on the FIRST ok_peer_fanout_degraded completion the verify used to abort
# RED, but a fresh `terraform apply -replace` boot of web-2 takes ~10 min to bind
# :9000. The fix waits out a bounded fresh-boot window then re-POSTs the fan-out
# EXACTLY once (max 2 web-1 swaps total). These tests prove the retry fires when it
# should, is BOUNDED (P0: exactly one re-POST even for a static-start_ts unbound
# host — never zero, never many), stays terminal on genuine failure/budget
# exhaustion (no green-on-timeout), and preserves every legacy invariant.
#
# The network is removed from the assertion path via three injectable seams the
# script honors (unset in prod → real curl / POST / wall-clock):
#   DEPLOY_STATUS_SOURCE_CMD  writes the next fixture body to $DS_BODY_FILE, echoes HTTP code
#   DEPLOY_POST_SINK          records each fan-out POST payload (one line per POST)
#   DEPLOY_POST_CODE_CMD      echoes the HTTP code for each POST (defaults 202)
# Fixtures are synthesized single-line JSON (no real tokens; cq-test-fixtures-synthesized-only).
#
# Run: bash apps/web-platform/infra/deploy-status-fanout-verify.test.sh
# Registered in .github/workflows/infra-validation.yml.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$DIR/scripts/deploy-status-fanout-verify.sh"
FIXTURES="$DIR/fixtures/deploy-status"

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() {
  fails=$((fails + 1))
  echo "FAIL: $1" >&2
}

[ -f "$SCRIPT" ] || { echo "FAIL: script not found at $SCRIPT" >&2; exit 1; }
[ -d "$FIXTURES" ] || { echo "FAIL: fixtures dir not found at $FIXTURES" >&2; exit 1; }

# jq empty every fixture BEFORE wiring it in (the #6030 forget-fixture brace-typo lesson).
for f in "$FIXTURES"/*.json; do
  jq empty "$f" 2>/dev/null || { echo "FAIL: fixture $f is not valid JSON" >&2; exit 1; }
done

# ── Test harness ────────────────────────────────────────────────────────────
# Inputs via env:
#   SEQ         space-separated fixture basenames (no .json). Position contract:
#               SEQ[0] = the baseline read, SEQ[1] = the trigger's internal
#               _get_status re-read (tag-downgrade guard), SEQ[2..] = the verify
#               polls — so every SEQ pads two leading settled bodies before the
#               first verify body. The popper clamps to the LAST body once the
#               sequence is exhausted (a real static host re-emits the same
#               deploy-status until a re-swap).
#   WINDOW      FRESH_BOOT_WINDOW_S (default 0 → retry fires on the first degraded)
#   RETRY_MAX   DEGRADED_RETRY_MAX (default 1)
#   ROSTER      WEB_HOST_PRIVATE_IPS (default the 2-host single-peer roster)
#   POST_CODES  space-separated HTTP codes returned per POST (default all 202)
#   MAXATT      STATUS_POLL_MAX_ATTEMPTS (default 6)
#   OPCTX       OP_CONTEXT (default recreate)
# Outputs via globals: RC, OUT, POSTS, GHOUT
run_verify() {
  local tmp
  tmp="$(mktemp -d)"
  local seqf="$tmp/seq.txt" idxf="$tmp/idx" bodyf="$tmp/body"
  local sink="$tmp/posts" codef="$tmp/codes" codeidx="$tmp/codeidx" ghout="$tmp/ghout"

  # Each fixture is already newline-terminated → one deploy-status body per line
  # (a second echo would inject blank lines that desync the popper sequence).
  : > "$seqf"
  local name
  for name in $SEQ; do
    cat "$FIXTURES/$name.json" >> "$seqf"
  done
  echo 1 > "$idxf"

  : > "$codef"
  local c
  for c in ${POST_CODES:-}; do echo "$c" >> "$codef"; done
  echo 1 > "$codeidx"

  # Stateful sequence popper: emit the i-th fixture body to $DS_BODY_FILE, clamp to
  # the last line once exhausted, advance the index file (persists across the
  # subshell command substitutions the script uses).
  cat > "$tmp/status.sh" <<'POP'
i=$(cat "$IDX_FILE"); n=$(wc -l < "$SEQ_FILE"); line=$i
[ "$line" -gt "$n" ] && line=$n
sed -n "${line}p" "$SEQ_FILE" > "$DS_BODY_FILE"
echo $((i + 1)) > "$IDX_FILE"
printf '200'
POP

  # Per-POST HTTP code popper (defaults 202 once the list is exhausted).
  cat > "$tmp/postcode.sh" <<'PC'
i=$(cat "$CODE_IDX"); n=$(wc -l < "$CODE_FILE")
if [ "$n" -eq 0 ] || [ "$i" -gt "$n" ]; then printf '202'; else sed -n "${i}p" "$CODE_FILE" | tr -d '\n'; fi
echo $((i + 1)) > "$CODE_IDX"
PC

  OUT=$(
    SEQ_FILE="$seqf" IDX_FILE="$idxf" DS_BODY_FILE="$bodyf" \
    CODE_FILE="$codef" CODE_IDX="$codeidx" \
    DEPLOY_STATUS_SOURCE_CMD="bash $tmp/status.sh" \
    DEPLOY_POST_SINK="$sink" DEPLOY_POST_CODE_CMD="bash $tmp/postcode.sh" \
    WEBHOOK_SECRET=test CF_ACCESS_CLIENT_ID=test CF_ACCESS_CLIENT_SECRET=test \
    WEB_HOST_PRIVATE_IPS="${ROSTER:-10.0.1.10,10.0.1.11}" \
    STATUS_POLL_MAX_ATTEMPTS="${MAXATT:-6}" STATUS_POLL_INTERVAL_S=0 SETTLE_SECONDS=0 \
    DEGRADED_RETRY_MAX="${RETRY_MAX:-1}" FRESH_BOOT_WINDOW_S="${WINDOW:-0}" \
    OP_CONTEXT="${OPCTX:-recreate}" GITHUB_OUTPUT="$ghout" \
    bash "$SCRIPT" 2>&1
  )
  RC=$?
  if [ -f "$sink" ]; then POSTS=$(wc -l < "$sink" | tr -d ' '); else POSTS=0; fi
  GHOUT=$(cat "$ghout" 2>/dev/null || echo "")
  rm -rf "$tmp"
}

# ── AC1: retries degraded→degraded→ok instead of aborting on first degraded ──
SEQ="settled-v1 settled-v1 degraded-v1-s200 settled-v1 degraded-v1-s200 ok-v1-s300" WINDOW=0 MAXATT=8 run_verify
if [ "$RC" -eq 0 ]; then pass; else fail "AC1: degraded→degraded→ok should exit 0 (retry), got rc=$RC. OUT: $OUT"; fi

# ── AC2: all-degraded (fresh cycle re-degrades after retry) → terminal exit 1 ──
# After the single re-POST a NEW cycle (start_ts=400) also degrades → retry cap
# exhausted → terminal ::error:: (NO green-on-timeout).
SEQ="settled-v1 settled-v1 degraded-v1-s200 settled-v1 degraded-v1-s400" WINDOW=0 MAXATT=8 run_verify
if [ "$RC" -eq 1 ]; then pass; else fail "AC2: all-degraded should exit 1, got rc=$RC"; fi
if printf '%s' "$OUT" | grep -q '::error::'; then pass; else fail "AC2: terminal path must print an ::error:: recovery message. OUT: $OUT"; fi
# Positively prove the retry FIRED before terminal exhaustion (not a retry-never-fired
# abort) — the discriminating signal is POSTS==2, independent of message wording.
if [ "$POSTS" -eq 2 ]; then pass; else fail "AC2: must retry once (POSTS==2) before terminal RED, got $POSTS"; fi

# ── AC3: web-1 re-swap bound — exactly 2 fan-out POSTs (initial + 1 retry) ──
SEQ="settled-v1 settled-v1 degraded-v1-s200 settled-v1 degraded-v1-s200 ok-v1-s300" WINDOW=0 MAXATT=8 run_verify
if [ "$POSTS" -eq 2 ]; then pass; else fail "AC3: DEGRADED_RETRY_MAX=1 must cap at 2 POSTs, got $POSTS"; fi

# ── AC3b: single retry is GATED on FRESH_BOOT_WINDOW_S ──
# Large window → the retry never fires within the poll budget → only the initial
# POST is recorded (proves the re-POST is gated, not immediate).
SEQ="settled-v1 settled-v1 degraded-v1-s200" WINDOW=100000 MAXATT=5 run_verify
if [ "$POSTS" -eq 1 ]; then pass; else fail "AC3b: with a large window only the initial POST should fire, got $POSTS"; fi
if [ "$RC" -eq 1 ]; then pass; else fail "AC3b: all-degraded within budget should exit 1, got rc=$RC"; fi

# ── AC3c: lock_contention is RETRYABLE, not terminal ──
SEQ="settled-v1 settled-v1 lock-contention-s200 ok-v1-s300" WINDOW=0 MAXATT=6 run_verify
if [ "$RC" -eq 0 ]; then pass; else fail "AC3c: lock_contention then ok should exit 0 (retryable), got rc=$RC. OUT: $OUT"; fi

# ── AC3d (P0 regression guard): SAME static start_ts across many polls → EXACTLY one retry ──
# A real unbound fresh boot re-emits the SAME degraded start_ts every poll. Marking
# the start_ts consumed on FIRST sight (the P0 bug) would make the retry unreachable
# (0 POSTs beyond the initial). Marking it only when the retry fires yields exactly
# one re-POST → 2 total. Never zero, never many.
SEQ="settled-v1 settled-v1 degraded-v1-s200" WINDOW=0 MAXATT=8 run_verify
if [ "$POSTS" -eq 2 ]; then pass; else fail "AC3d: static-start_ts unbound host must fire EXACTLY one retry (2 POSTs), got $POSTS. OUT: $OUT"; fi
if [ "$RC" -eq 1 ]; then pass; else fail "AC3d: static-start_ts all-degraded should exhaust budget → exit 1, got rc=$RC"; fi

# ── AC3e: _retrigger_fanout REASSIGNS DEPLOY_TAG so a newer-tag ok is accepted ──
# A newer tag lands during the wait (retry re-read sees v1.1.0); the eventual ok
# reports v1.1.0. Without the DEPLOY_TAG rebind, ok@v1.1.0 never matches → RED.
SEQ="settled-v1 settled-v1 degraded-v1-s200 settled-v2-s250 ok-v2-s300" WINDOW=0 MAXATT=8 run_verify
if [ "$RC" -eq 0 ]; then pass; else fail "AC3e: newer tag during retry should still exit 0 (DEPLOY_TAG reassigned), got rc=$RC. OUT: $OUT"; fi

# ── AC3f: a non-202 re-POST is TERMINAL exit 1 (not absorbed into budget) ──
# Initial POST 202, retry POST 403 → terminal ::error:: with recovery message.
SEQ="settled-v1 settled-v1 degraded-v1-s200 settled-v1" WINDOW=0 MAXATT=8 POST_CODES="202 403" run_verify
if [ "$RC" -eq 1 ]; then pass; else fail "AC3f: a 403 re-POST should exit 1, got rc=$RC"; fi
if printf '%s' "$OUT" | grep -q '403'; then pass; else fail "AC3f: the non-202 error must surface the HTTP code. OUT: $OUT"; fi

# ── AC4: roster invariant — ROSTER_COUNT!=2 → exit 1 ──
SEQ="settled-v1" ROSTER="10.0.1.10" MAXATT=3 run_verify
if [ "$RC" -eq 1 ]; then pass; else fail "AC4-roster: single-host roster should exit 1, got rc=$RC"; fi
if printf '%s' "$OUT" | grep -q 'exactly one peer'; then pass; else fail "AC4-roster: must print the single-peer guard error. OUT: $OUT"; fi

# ── AC4: roster invariant — ZERO-count roster must FAIL LOUD, not abort silently ──
# `grep -c` exits 1 on zero matches; without the `|| true` guard the ROSTER_COUNT
# assignment aborts under set -e BEFORE the tailored error (silent rc=1).
SEQ="settled-v1" ROSTER="garbage,nothing" MAXATT=3 run_verify
if [ "$RC" -eq 1 ]; then pass; else fail "AC4-roster0: zero-count roster should exit 1, got rc=$RC"; fi
if printf '%s' "$OUT" | grep -q 'exactly one peer'; then pass; else fail "AC4-roster0: zero-count roster must print the single-peer guard error (not abort silently). OUT: $OUT"; fi

# ── AC4: staleness — a stale (start_ts <= baseline) 'ok' is NOT accepted as success ──
SEQ="settled-v1 settled-v1 stale-ok-s50" WINDOW=0 MAXATT=5 run_verify
if [ "$RC" -eq 1 ]; then pass; else fail "AC4-staleness: a stale ok must NOT be accepted (should exit 1 on budget), got rc=$RC"; fi

# ── AC4: tag validation — a TRULY-invalid current tag (garbage) → exit 1 ──
SEQ="garbage-tag" MAXATT=3 run_verify
if [ "$RC" -eq 1 ]; then pass; else fail "AC4-tag: a truly-invalid baseline tag ('garbage!') should exit 1, got rc=$RC"; fi

# ── AC4: tag validation — an EMPTY current tag still aborts (the comment at the guard
# advertises "empty / garbage still abort"; garbage is covered above, empty here). ──
SEQ="empty-tag" MAXATT=3 run_verify
if [ "$RC" -eq 1 ]; then pass; else fail "AC4-tag-empty: an empty baseline tag should exit 1, got rc=$RC"; fi

# ── AC4-latest: web-1 on the floating :latest is TOLERATED (can't downgrade web-1) → the
# verify proceeds to a successful web-2 fan-out instead of aborting on the baseline read. ──
SEQ="latest-tag latest-tag ok-latest-s300" WINDOW=0 MAXATT=5 run_verify
if [ "$RC" -eq 0 ]; then pass; else fail "AC4-latest: a 'latest' baseline tag should be tolerated and reach a successful verify (exit 0), got rc=$RC. OUT: $OUT"; fi

# ── AC4-latest-resolve: a :latest baseline whose trigger re-read reports a PINNED version
# is a path only reachable because the baseline now tolerates `latest`. The downgrade guard
# reassigns DEPLOY_TAG latest→vX.Y.Z (never a downgrade) and the poll matches the pinned tag.
# Proves the durable-:latest-resolved-at-source case (guard comment / #6060) works end-to-end. ──
SEQ="latest-tag settled-v2-s250 ok-v2-s300" WINDOW=0 MAXATT=5 run_verify
if [ "$RC" -eq 0 ]; then pass; else fail "AC4-latest-resolve: latest baseline + pinned re-read should exit 0, got rc=$RC. OUT: $OUT"; fi
if printf '%s' "$GHOUT" | grep -q '^deployed_tag=v1.1.0$'; then pass; else fail "AC4-latest-resolve: DEPLOY_TAG must reassign latest→v1.1.0 (emitted to GITHUB_OUTPUT). GHOUT: $GHOUT"; fi

# ── AC4: fail-loud on an UNEXPECTED reason (exit_code=0, reason ∉ {ok, *_degraded}) ──
SEQ="settled-v1 settled-v1 unexpected-reason-s300" WINDOW=0 MAXATT=5 run_verify
if [ "$RC" -eq 1 ]; then pass; else fail "AC4-unexpected: an unexpected reason should terminal-exit 1, got rc=$RC"; fi
if printf '%s' "$OUT" | grep -q 'unexpected reason'; then pass; else fail "AC4-unexpected: must print the unexpected-reason ::error::. OUT: $OUT"; fi

# ── AC4: fail-loud on a genuine deploy failure (exit_code=1, reason≠lock_contention) ──
SEQ="settled-v1 settled-v1 deploy-failed-s300" WINDOW=0 MAXATT=5 run_verify
if [ "$RC" -eq 1 ]; then pass; else fail "AC4-failed: a non-lock_contention exit_code=1 should terminal-exit 1, got rc=$RC"; fi
if printf '%s' "$OUT" | grep -q 'deploy fan-out failed'; then pass; else fail "AC4-failed: must print the deploy-failed ::error::. OUT: $OUT"; fi

# ── AC6: emits deployed_tag=<tag> to $GITHUB_OUTPUT for the warm-standby summary ──
SEQ="settled-v1 settled-v1 ok-v1-s300" WINDOW=0 MAXATT=5 run_verify
if printf '%s' "$GHOUT" | grep -q '^deployed_tag=v1.0.0$'; then pass; else fail "AC6: script must emit deployed_tag= to GITHUB_OUTPUT. GHOUT: $GHOUT"; fi

# ── AC (context): OP_CONTEXT selects the recovery-message wording ──
SEQ="settled-v1 settled-v1 degraded-v1-s200 settled-v1 degraded-v1-s400" WINDOW=0 MAXATT=8 OPCTX="warm-standby" run_verify
if printf '%s' "$OUT" | grep -qi 'Attach landed'; then pass; else fail "OP_CONTEXT=warm-standby recovery message should say 'Attach landed'. OUT: $OUT"; fi
SEQ="settled-v1 settled-v1 degraded-v1-s200 settled-v1 degraded-v1-s400" WINDOW=0 MAXATT=8 OPCTX="recreate" run_verify
if printf '%s' "$OUT" | grep -qi 'Recreate landed'; then pass; else fail "OP_CONTEXT=recreate recovery message should say 'Recreate landed'. OUT: $OUT"; fi

total=$((passes + fails))
echo "deploy-status-fanout-verify: ${passes} passed, ${fails} failed (${total} assertions)"
[ "$fails" -eq 0 ]
