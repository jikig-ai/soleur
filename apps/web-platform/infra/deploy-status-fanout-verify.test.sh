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
# The network is removed from the assertion path via four injectable seams the
# script honors (unset in prod → real curl / POST / wall-clock):
#   DEPLOY_STATUS_SOURCE_CMD  writes the next fixture body to $DS_BODY_FILE, echoes HTTP code
#   DEPLOY_POST_SINK          records each fan-out POST payload (one line per POST)
#   DEPLOY_POST_CODE_CMD      echoes the HTTP code for each POST (defaults 202)
#   HEALTH_SOURCE_CMD         echoes web-1's /health `.version` string (#6353 — the tag
#                             the fan-out re-swaps is resolved from HERE, never .tag)
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
#               SEQ[0] = the baseline read, SEQ[1..] = the verify polls. #6353
#               removed the trigger's internal _get_status re-read (the re-swap tag
#               now resolves from /health via HEALTH_SEQ, not the deploy-status .tag),
#               so the trigger consumes NO deploy-status body — one leading pad, not
#               two. Legacy SEQs that still carry a second leading `settled-v1`
#               (start_ts=100) are harmless: that body is pre-trigger-skipped by the
#               staleness gate (start_ts <= baseline) rather than eaten by the trigger.
#               The popper clamps to the LAST body once the sequence is exhausted (a
#               real static host re-emits the same deploy-status until a re-swap).
#   WINDOW      FRESH_BOOT_WINDOW_S (default 0 → retry fires on the first degraded)
#   RETRY_MAX   DEGRADED_RETRY_MAX (default 1)
#   ROSTER      WEB_HOST_PRIVATE_IPS (default the 2-host single-peer roster)
#   POST_CODES  space-separated HTTP codes returned per POST (default all 202)
#   MAXATT      STATUS_POLL_MAX_ATTEMPTS (default 6)
#   OPCTX       OP_CONTEXT (default recreate)
#   HEALTH_SEQ  space-separated web-1 /health `.version` strings, popped once per
#               _resolve_known_good_tag() call (baseline seed, initial trigger, each
#               retrigger — clamp to last). Default "1.0.0" (matches the v1.0.0
#               fixture family so the poll TAG==DEPLOY_TAG match still holds). A token
#               of "-" echoes an EMPTY .version (simulates /health unreachable). This
#               DEFAULT keeps every case network-free — with no seam the resolve would
#               curl app.soleur.ai/health in CI (spec-flow P1).
# Outputs via globals: RC, OUT, POSTS, POSTBODIES, GHOUT
run_verify() {
  local tmp
  tmp="$(mktemp -d)"
  local seqf="$tmp/seq.txt" idxf="$tmp/idx" bodyf="$tmp/body"
  local sink="$tmp/posts" codef="$tmp/codes" codeidx="$tmp/codeidx" ghout="$tmp/ghout"
  local healthf="$tmp/health.txt" hidxf="$tmp/hidx"

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

  # /health `.version` sequence (#6353): one line per version, popped per
  # _resolve_known_good_tag() call, clamped to the last line. Default 1.0.0 so every
  # legacy case resolves DEPLOY_TAG=v1.0.0 (matching the v1.0.0 fixtures) with NO real
  # network curl. "-" → an empty .version (drives the /health-unreachable abort).
  : > "$healthf"
  local hv
  for hv in ${HEALTH_SEQ:-1.0.0}; do echo "$hv" >> "$healthf"; done
  echo 1 > "$hidxf"

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

  # /health `.version` popper: emit the i-th version (clamp to last once exhausted),
  # advance the index. A "-" line means an empty .version (the resolver then aborts
  # loud — the /health-unreachable case). stdout is the bare version string only.
  cat > "$tmp/health.sh" <<'HP'
i=$(cat "$HIDX_FILE"); n=$(wc -l < "$HEALTH_FILE"); line=$i
[ "$line" -gt "$n" ] && line=$n
if [ "$n" -eq 0 ]; then echo $((i + 1)) > "$HIDX_FILE"; exit 0; fi
v=$(sed -n "${line}p" "$HEALTH_FILE")
echo $((i + 1)) > "$HIDX_FILE"
[ "$v" = "-" ] && v=""
printf '%s' "$v"
HP

  OUT=$(
    SEQ_FILE="$seqf" IDX_FILE="$idxf" DS_BODY_FILE="$bodyf" \
    CODE_FILE="$codef" CODE_IDX="$codeidx" \
    HEALTH_FILE="$healthf" HIDX_FILE="$hidxf" \
    DEPLOY_STATUS_SOURCE_CMD="bash $tmp/status.sh" \
    DEPLOY_POST_SINK="$sink" DEPLOY_POST_CODE_CMD="bash $tmp/postcode.sh" \
    HEALTH_SOURCE_CMD="bash $tmp/health.sh" \
    WEBHOOK_SECRET=test CF_ACCESS_CLIENT_ID=test CF_ACCESS_CLIENT_SECRET=test \
    WEB_HOST_PRIVATE_IPS="${ROSTER:-10.0.1.10,10.0.1.11}" \
    STATUS_POLL_MAX_ATTEMPTS="${MAXATT:-6}" STATUS_POLL_INTERVAL_S=0 SETTLE_SECONDS=0 \
    DEGRADED_RETRY_MAX="${RETRY_MAX:-1}" FRESH_BOOT_WINDOW_S="${WINDOW:-0}" \
    OP_CONTEXT="${OPCTX:-recreate}" GITHUB_OUTPUT="$ghout" \
    bash "$SCRIPT" 2>&1
  )
  RC=$?
  # Capture the POST-sink CONTENTS (not just the line count) BEFORE the tmp dir is
  # removed — assertions grep $POSTBODIES for the fan-out payload (semver present,
  # `latest` absent). A `! grep -q latest <deleted-file>` would return non-zero and
  # `!`-flip to a vacuous GREEN (spec-flow P0); assert against this captured string
  # with a POSITIVE anchor so an empty capture fails loudly.
  if [ -f "$sink" ]; then
    POSTS=$(wc -l < "$sink" | tr -d ' ')
    POSTBODIES=$(cat "$sink")
  else
    POSTS=0
    POSTBODIES=""
  fi
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

# ── AC4-tag (re-homed #6353): tag validation MOVED from the deploy-status `.tag` to
# web-1's /health `.version`. A non-semver /health value aborts LOUD at the baseline
# resolve — even when the deploy-status .tag is ALSO garbage, the .tag is never trusted
# as the re-swap tag source, and no fan-out POST fires. ──
SEQ="garbage-tag" HEALTH_SEQ="garbage!" MAXATT=3 run_verify
if [ "$RC" -eq 1 ]; then pass; else fail "AC4-tag: a non-semver /health .version ('garbage!') should abort exit 1, got rc=$RC. OUT: $OUT"; fi
if [ "$POSTS" -eq 0 ]; then pass; else fail "AC4-tag: a failed /health resolve must abort BEFORE any fan-out POST (no .tag fallback), got POSTS=$POSTS"; fi

# ── AC4-tag-empty (re-homed #6353): an EMPTY /health `.version` (unreachable / unparsed)
# aborts loud — never a silent fallback to the deploy-status `.tag`. ──
SEQ="empty-tag" HEALTH_SEQ="-" MAXATT=3 run_verify
if [ "$RC" -eq 1 ]; then pass; else fail "AC4-tag-empty: an empty /health .version should abort exit 1, got rc=$RC. OUT: $OUT"; fi
if [ "$POSTS" -eq 0 ]; then pass; else fail "AC4-tag-empty: an empty /health resolve must abort BEFORE any fan-out POST, got POSTS=$POSTS"; fi

# ── T-A (#6353, replaces AC4-latest): web-1's deploy-status .tag is polluted with
# `latest` (an inngest-restart writer) but /health reports a released 1.2.3 → the
# fan-out re-swaps web-1 at v1.2.3 (resolved from /health), NEVER `latest`. Proves the
# core wedge fix: the tag_malformed `latest` POST no longer happens. ──
SEQ="latest-tag latest-tag ok-v123-s300" HEALTH_SEQ="1.2.3" WINDOW=0 MAXATT=5 run_verify
if [ "$RC" -eq 0 ]; then pass; else fail "T-A: latest .tag + /health=1.2.3 should resolve v1.2.3 and reach exit 0, got rc=$RC. OUT: $OUT"; fi
if grep -q 'v1.2.3' <<<"$POSTBODIES"; then pass; else fail "T-A: the fan-out POST must carry the /health-resolved v1.2.3. POSTBODIES: $POSTBODIES"; fi
if ! grep -q 'latest' <<<"$POSTBODIES"; then pass; else fail "T-A: the fan-out POST must NEVER carry the polluted `latest` tag. POSTBODIES: $POSTBODIES"; fi

# ── T-B (#6353): /health unreachable (empty .version) → terminal exit 1 with a named
# ::error:: recovery message and ZERO fan-out POSTs — NO silent fallback to the .tag
# seed. Asserted under BOTH OP_CONTEXTs (the recovery-message wording diverges). ──
SEQ="latest-tag" HEALTH_SEQ="-" WINDOW=0 MAXATT=3 OPCTX="recreate" run_verify
if [ "$RC" -eq 1 ]; then pass; else fail "T-B/recreate: /health unreachable should terminal-exit 1, got rc=$RC. OUT: $OUT"; fi
if printf '%s' "$OUT" | grep -q '::error::'; then pass; else fail "T-B/recreate: must print a named ::error::. OUT: $OUT"; fi
if printf '%s' "$OUT" | grep -qi 'Recreate landed'; then pass; else fail "T-B/recreate: must carry the recreate recovery message. OUT: $OUT"; fi
if [ "$POSTS" -eq 0 ] && ! grep -q 'latest' <<<"$POSTBODIES"; then pass; else fail "T-B/recreate: must NOT POST (no `latest`, no .tag fallback), got POSTS=$POSTS POSTBODIES=$POSTBODIES"; fi
SEQ="latest-tag" HEALTH_SEQ="-" WINDOW=0 MAXATT=3 OPCTX="warm-standby" run_verify
if [ "$RC" -eq 1 ]; then pass; else fail "T-B/warm-standby: /health unreachable should terminal-exit 1, got rc=$RC. OUT: $OUT"; fi
if printf '%s' "$OUT" | grep -qi 'Attach landed'; then pass; else fail "T-B/warm-standby: must carry the warm-standby recovery message. OUT: $OUT"; fi

# ── T-C (#6353): /health reports a non-released version ('dev', BUILD_VERSION unset) →
# terminal exit 1 with a remediation ::error:: (minimal string-shape echo — the pure
# resolver's own suite covers the full non-semver rejection matrix). ──
SEQ="latest-tag" HEALTH_SEQ="dev" WINDOW=0 MAXATT=3 run_verify
if [ "$RC" -eq 1 ]; then pass; else fail "T-C: /health='dev' should terminal-exit 1, got rc=$RC. OUT: $OUT"; fi
if printf '%s' "$OUT" | grep -q '::error::'; then pass; else fail "T-C: non-semver /health must print a remediation ::error::. OUT: $OUT"; fi
if [ "$POSTS" -eq 0 ]; then pass; else fail "T-C: a non-semver /health resolve must abort BEFORE any POST, got POSTS=$POSTS"; fi

# ── T-D (#6353, replaces AC4-latest-resolve + AC3e): the _trigger_fanout RETRIGGER
# re-resolves the re-swap tag from /health too. During the fresh-boot wait /health
# advances 1.0.0 → 1.1.0; the SECOND (retrigger) POST carries v1.1.0. The deploy-status
# .tag stays v1.0.0 throughout, so a v1.1.0 POST can ONLY have come from /health — never
# the .tag (this is what flips RED on the unmodified script). ──
SEQ="settled-v1 settled-v1 degraded-v1-s200 settled-v1 degraded-v1-s400" HEALTH_SEQ="1.0.0 1.0.0 1.1.0" WINDOW=0 MAXATT=8 run_verify
if grep -q 'v1.1.0' <<<"$POSTBODIES"; then pass; else fail "T-D: the retrigger POST must carry the advanced /health v1.1.0. POSTBODIES: $POSTBODIES"; fi
if [ "$(printf '%s\n' "$POSTBODIES" | sed -n '2p' | grep -c 'v1.1.0')" -eq 1 ]; then pass; else fail "T-D: specifically the SECOND (retrigger) POST must carry v1.1.0. POSTBODIES: $POSTBODIES"; fi
if printf '%s' "$GHOUT" | grep -q '^deployed_tag=v1.1.0$'; then pass; else fail "T-D: DEPLOY_TAG must re-resolve latest→v1.1.0 from /health (emitted to GITHUB_OUTPUT). GHOUT: $GHOUT"; fi

# ── T-D-green (#6353): the retrigger-advanced tag is ACCEPTED end-to-end. During the
# fresh-boot wait /health advances 1.0.0 → 1.1.0; after the retrigger re-swaps at
# v1.1.0, web-2's `ok` completion at v1.1.0 matches DEPLOY_TAG → exit 0. Restores the
# RC==0 "advance-then-accept" coverage the deleted AC3e had (T-D above proves the POST
# payload but ends RC=1 on an unmatched slot). ──
SEQ="settled-v1 settled-v1 degraded-v1-s200 ok-v11-s300" HEALTH_SEQ="1.0.0 1.0.0 1.1.0" WINDOW=0 MAXATT=8 run_verify
if [ "$RC" -eq 0 ]; then pass; else fail "T-D-green: an ok completion at the /health-advanced v1.1.0 should exit 0, got rc=$RC. OUT: $OUT"; fi
if printf '%s' "$GHOUT" | grep -q '^deployed_tag=v1.1.0$'; then pass; else fail "T-D-green: accepted DEPLOY_TAG must be the /health-advanced v1.1.0. GHOUT: $GHOUT"; fi

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
