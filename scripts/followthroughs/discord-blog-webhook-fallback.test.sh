#!/usr/bin/env bash
# Exit-code harness for discord-blog-webhook-fallback.sh (generic post-secret
# publish verification probe for the follow-through sweeper).
#
# The probe's exit code IS its authorization artifact: sweep-followthroughs.sh
# closes the tracker on 0, comments FAIL on 1, renders 2 as NOT YET and 3 as
# CANNOT ESTABLISH. Cardinal sins: a vacuous 0 before the first post-secret
# publish has landed (the liveness gate exists so "zero events" is never
# measured against a producer that has not run); a 1 manufactured from a read
# failure (3 is the contract for an unmeasured window — the sweeper retries, it
# does not alarm); and a cutoff off-by-one (the bound is INCLUSIVE — an event
# stamped at exactly 2026-10-29T17:00:00Z is post-secret and must FAIL).
#
# The SUT runs under `env -i` exactly as the sweeper runs it, with a
# PATH-shimmed `curl` that serves a synthesized events payload (records argv +
# the stdin-config bearer, fails with a chosen rc or HTTP status) and a
# synthesized content dir reached through the probe's
# DISCORD_BLOG_WEBHOOK_FALLBACK_CONTENT_DIR seam. All timestamps are pinned to
# the probe's fixed cutoff, so every case is deterministic. Fixtures are
# synthesized (cq-test-fixtures-synthesized-only): no live response is
# captured.

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/discord-blog-webhook-fallback.sh"
fails=0; total=0
pass() { total=$((total + 1)); printf '  PASS: %s\n' "$1"; }
fail() { total=$((total + 1)); printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

[[ -f "$SUT" ]] || { echo "FATAL: SUT not found at $SUT" >&2; exit 1; }
[[ -x "$SUT" ]] || { echo "FATAL: SUT not executable at $SUT" >&2; exit 1; }

# Instrument self-test (ADR-193): both counters must move before any verdict is
# trusted.
_p0=$total; pass "instrument: pass() moves the counter" >/dev/null; _f0=$fails
fail "instrument: fail() moves the counter" 2>/dev/null
if [[ $total -ne $((_p0 + 2)) || $fails -ne $((_f0 + 1)) ]]; then
  printf 'FATAL: instrument self-test -- pass()/fail() did not both move their counters\n' >&2; exit 1
fi
total=$_p0; fails=$_f0

# Byte-for-byte copy of the canonical assertion in plugins/soleur/test/test-helpers.sh
# (fixture-dir-operand-assert.test.sh drift-checks every copy). Guards the scratch root
# before any write lands under it.
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

WORK="$(mktemp -d -t dbwf-test.XXXXXXXX)" || { echo "FATAL: no scratch root" >&2; exit 1; }
assert_fixture_dir "$WORK"
readonly WORK
trap 'rm -rf -- "$WORK" 2>/dev/null' EXIT
mkdir -p "$WORK/bin" "$WORK/content"
CALLS="$WORK/calls.log"

# Pinned bounds (match the SUT literals).
CUTOFF="2026-10-29T17:00:00Z"
IN_WINDOW="2026-11-03T14:05:00+00:00"    # after the cutoff — the +00:00 serializer shape
PRE_CUTOFF="2026-10-29T12:00:00+00:00"   # before the cutoff
AT_CUTOFF="2026-10-29T17:00:00+00:00"    # exactly at the inclusive bound, +00:00 form

# ── Synthesized fixtures ─────────────────────────────────────────────────────
# Distribution-content markdown in the shape scripts/content-publisher.sh scans:
# a frontmatter block between two `---` lines carrying publish_date / channels /
# status.
md_file() { # <path> <status> <publish_date> <channels-csv>
  printf -- '---\ntitle: "Fixture"\npublish_date: %s\nchannels: %s\nstatus: %s\n---\n\nFixture body.\n' \
    "$3" "$4" "$2" > "$1"
}
event_row() { # <title> <timestamp>
  printf '{"title":"%s","timestamp":"%s"}' "$1" "$2"
}
events_json() { # event_row fragments as $@
  local rows="" r
  for r in "$@"; do rows+="${rows:+,}$r"; done
  printf '{"data":[%s]}' "$rows"
}

# ── curl stub: dispatches on the pinned events URL, honours -w, records argv,
#    reads the stdin-config bearer, fails on demand ───────────────────────────
cat > "$WORK/bin/curl" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
cfg="$(dirname "$0")/.."
printf 'curl %s\n' "$*" >> "$cfg/calls.log"
url=""; want_code=0
args=("$@")
for a in "${args[@]}"; do [[ "$a" == "-" ]] && { cat >> "$cfg/stdin.log"; break; }; done
for (( i = 0; i < ${#args[@]}; i++ )); do
  case "${args[$i]}" in
    -w) want_code=1; i=$((i+1)) ;;
    -H|--noproxy|--config|-m|-D) i=$((i+1)) ;;
    https://*) url="${args[$i]}" ;;
  esac
done
rc_file="$cfg/curl.rc"; [[ -f "$rc_file" ]] && { rc="$(<"$rc_file")"; [[ "$rc" != "0" ]] && exit "$rc"; }
case "$url" in
  https://de.sentry.io/api/0/organizations/jikigai-eu/events/*) ;;
  *) printf 'stub: unexpected url %s\n' "$url" >&2; printf 'OFFHOST %s\n' "$url" >> "$cfg/calls.log"; exit 99 ;;
esac
code="$(cat "$cfg/events.code" 2>/dev/null || echo 200)"
[[ -f "$cfg/events.json" ]] && cat "$cfg/events.json"
[[ "$want_code" == 1 ]] && printf '\nHTTP_STATUS:%s\n' "$code"
exit 0
STUB
chmod 0755 "$WORK/bin/curl"

# reset [md-fixture-args...] — clean content dir + empty events + clear stub state.
reset_fixtures() {
  rm -f "$WORK"/content/*.md "$WORK/curl.rc" "$WORK/events.code" "$WORK/events.json" 2>/dev/null
  : > "$CALLS"; : > "$WORK/stdin.log"
  events_json > "$WORK/events.json"
}

# run_case <desc> <expected-rc> [env assignments...] -- SUT argv via $SUT_ARGV
run_case() {
  local desc="$1" expected="$2"; shift 2
  local rc=0 out
  out="$(env -i PATH="$WORK/bin:/usr/bin:/bin" HOME="$WORK" \
    SENTRY_ACTIONS_RO_TOKEN=fakesentrytoken123 GH_TOKEN=fakeghtoken456 \
    DISCORD_BLOG_WEBHOOK_FALLBACK_CONTENT_DIR="$WORK/content" \
    "$@" bash "$SUT" ${SUT_ARGV:-} 2>&1)"; rc=$?
  if [[ "$rc" -eq "$expected" ]]; then pass "$desc"; else fail "$desc (expected rc=$expected, got rc=$rc; out: $(printf '%s' "$out" | tail -4 | tr '\n' '|'))"; fi
  unset SUT_ARGV
}

echo "== discord-blog-webhook-fallback.sh arms =="

# ── LIVENESS: every non-qualifying shape must exit 2 before any Sentry read ──
reset_fixtures
run_case "empty content dir -> NOT YET" 2

reset_fixtures
md_file "$WORK/content/2026-11-03-scheduled.md" scheduled 2026-11-03 "x, bluesky, discord, linkedin-personal"
run_case "scheduled (not published) discord file -> NOT YET" 2

reset_fixtures
md_file "$WORK/content/2026-10-20-old.md" published 2026-10-20 "x, discord"
run_case "published discord file below the date floor -> NOT YET" 2

reset_fixtures
md_file "$WORK/content/2026-11-03-nodiscord.md" published 2026-11-03 "x, bluesky, linkedin-personal"
run_case "published in-window file without discord channel -> NOT YET" 2

reset_fixtures
md_file "$WORK/content/2026-11-03-substring.md" published 2026-11-03 "x, discord-blog"
run_case "channels token merely containing 'discord' -> NOT YET (word match)" 2

# ── qualifying liveness + Sentry arms ────────────────────────────────────────
reset_fixtures
md_file "$WORK/content/2026-11-03-post.md" published 2026-11-03 "x, bluesky, discord, linkedin-personal"
run_case "qualifying publish + zero events -> PASS" 0

reset_fixtures
md_file "$WORK/content/2026-11-03-post.md" published 2026-11-03 "x, discord"
md_file "$WORK/content/2026-11-04-scheduled.md" scheduled 2026-11-04 "x, discord"
events_json "$(event_row "cron-content-publisher" "$PRE_CUTOFF")" > "$WORK/events.json"
run_case "qualifying + scheduled sibling + only pre-cutoff events -> PASS" 0

reset_fixtures
md_file "$WORK/content/2026-11-03-post.md" published 2026-11-03 "x, discord"
events_json "$(event_row "DISCORD_BLOG_WEBHOOK_URL unset in publisher env — posting via fallback" "$IN_WINDOW")" > "$WORK/events.json"
run_case "qualifying + in-window marker event -> FAIL" 1

reset_fixtures
md_file "$WORK/content/2026-11-03-post.md" published 2026-11-03 "x, discord"
events_json "$(event_row "marker" "$AT_CUTOFF")" > "$WORK/events.json"
run_case "event at exactly the cutoff -> FAIL (inclusive bound)" 1

reset_fixtures
md_file "$WORK/content/2026-11-03-post.md" published 2026-11-03 "x, discord"
events_json "$(event_row "marker" "$IN_WINDOW")" "$(event_row "older" "$PRE_CUTOFF")" > "$WORK/events.json"
run_case "one in-window + one pre-cutoff event -> FAIL" 1

# ── measure failures → CANNOT ESTABLISH ──────────────────────────────────────
reset_fixtures
md_file "$WORK/content/2026-11-03-post.md" published 2026-11-03 "x, discord"
echo 500 > "$WORK/events.code"
run_case "Sentry HTTP 500 -> CANNOT ESTABLISH" 3

reset_fixtures
md_file "$WORK/content/2026-11-03-post.md" published 2026-11-03 "x, discord"
printf 'this is not json' > "$WORK/events.json"
run_case "non-JSON events body -> CANNOT ESTABLISH" 3

reset_fixtures
md_file "$WORK/content/2026-11-03-post.md" published 2026-11-03 "x, discord"
echo 7 > "$WORK/curl.rc"
run_case "curl transport failure -> CANNOT ESTABLISH" 3

reset_fixtures
md_file "$WORK/content/2026-11-03-post.md" published 2026-11-03 "x, discord"
events_json "$(event_row "marker" "not-a-timestamp")" > "$WORK/events.json"
run_case "unparseable event timestamp -> CANNOT ESTABLISH" 3

# ── credentials / destination pins ───────────────────────────────────────────
reset_fixtures
md_file "$WORK/content/2026-11-03-post.md" published 2026-11-03 "x, discord"
out="$(env -i PATH="$WORK/bin:/usr/bin:/bin" HOME="$WORK" \
  GH_TOKEN=t DISCORD_BLOG_WEBHOOK_FALLBACK_CONTENT_DIR="$WORK/content" \
  bash "$SUT" 2>&1)"; rc=$?
if [[ "$rc" -eq 3 ]]; then pass "missing SENTRY_ACTIONS_RO_TOKEN -> CANNOT ESTABLISH"; else fail "missing SENTRY_ACTIONS_RO_TOKEN -> CANNOT ESTABLISH (rc=$rc)"; fi

out="$(env -i PATH="$WORK/bin:/usr/bin:/bin" HOME="$WORK" \
  SENTRY_ACTIONS_RO_TOKEN='bad token with space' GH_TOKEN=t \
  DISCORD_BLOG_WEBHOOK_FALLBACK_CONTENT_DIR="$WORK/content" bash "$SUT" 2>&1)"; rc=$?
if [[ "$rc" -eq 3 ]]; then pass "bad-shaped token -> CANNOT ESTABLISH"; else fail "bad-shaped token -> CANNOT ESTABLISH (rc=$rc)"; fi

run_case "SENTRY_ORG override -> CANNOT ESTABLISH" 3 SENTRY_ORG=other-org
run_case "SENTRY_API_HOST override -> CANNOT ESTABLISH" 3 SENTRY_API_HOST=evil.example.com

# ── xtrace refusal ───────────────────────────────────────────────────────────
out="$(env -i PATH="$WORK/bin:/usr/bin:/bin" HOME="$WORK" \
  SENTRY_ACTIONS_RO_TOKEN=t GH_TOKEN=t \
  DISCORD_BLOG_WEBHOOK_FALLBACK_CONTENT_DIR="$WORK/content" bash -x "$SUT" 2>&1)"; rc=$?
if [[ "$rc" -eq 78 ]]; then pass "xtrace with creds -> refusal 78"; else fail "xtrace with creds -> refusal 78 (rc=$rc)"; fi

out="$(env -i PATH="$WORK/bin:/usr/bin:/bin" HOME="$WORK" \
  DISCORD_BLOG_WEBHOOK_FALLBACK_CONTENT_DIR="$WORK/content" bash -x "$SUT" 2>&1)"; rc=$?
if [[ "$rc" -eq 3 ]]; then pass "xtrace with NO creds -> refusal stays open, falls to prereq (3)"; else fail "xtrace with NO creds -> 3 expected (rc=$rc)"; fi

# ── wire assertions: pinned query, stdin-config bearer, never argv ───────────
reset_fixtures
md_file "$WORK/content/2026-11-03-post.md" published 2026-11-03 "x, discord"
env -i PATH="$WORK/bin:/usr/bin:/bin" HOME="$WORK" \
  SENTRY_ACTIONS_RO_TOKEN=t GH_TOKEN=t \
  DISCORD_BLOG_WEBHOOK_FALLBACK_CONTENT_DIR="$WORK/content" \
  bash "$SUT" >/dev/null 2>&1
if grep -q 'https://de.sentry.io/api/0/organizations/jikigai-eu/events/' "$CALLS"; then
  pass "curl reached the pinned events URL"
else
  fail "curl reached the pinned events URL (calls: $(cat "$CALLS"))"
fi
for pin in 'sort=-timestamp' 'statsPeriod=30d' 'per_page=10' 'field=title' 'field=timestamp'; do
  if grep -qF -- "$pin" "$CALLS"; then
    pass "events URL carries $pin"
  else
    fail "events URL carries $pin (calls: $(cat "$CALLS"))"
  fi
done
if grep -q 'header = "Authorization: Bearer ' "$WORK/stdin.log"; then
  pass "bearer rides the stdin config channel (never argv)"
else
  fail "bearer rides the stdin config channel (stdin.log: $(cat "$WORK/stdin.log"))"
fi
if grep -q 'Authorization' "$CALLS"; then
  fail "bearer must never reach argv"
else
  pass "bearer never reaches argv"
fi

# ── argv-free: extra argv must not change the verdict (sweeper execs argv-free)
reset_fixtures
md_file "$WORK/content/2026-11-03-post.md" published 2026-11-03 "x, discord"
SUT_ARGV="unexpected-arg --bogus"
run_case "SUT_ARGV present -> probe ignores argv, still PASS" 0

printf '\n%d assertions, %d failure(s)\n' "$total" "$fails"
[[ "$fails" -eq 0 ]]
