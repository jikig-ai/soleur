#!/usr/bin/env bash
# Follow-through soak for #9678: after the compact collector output shipped, the community-monitor
# digest must stop labelling Discord and GitHub `partial` with cause `output-too-large`.
#
# #9678: the spawned agent has no file tools, so a collector line past the Bash tool's inline limit
# (30,000 characters) was unreadable and the prompt forced the row to `partial` / `output-too-large`
# (the 2026-10-06 digest showed it on both Discord and GitHub, with zeros produced by the
# truncation). The cron handler now sets SOLEUR_COLLECTOR_COMPACT=1 and each collector prints one
# compact line. This probe grades the EFFECT, from the committed digests only: no credentials, no
# network, no API.
#
# Exit semantics (the sweeper's contract, scripts/sweep-followthroughs.sh):
#   0 = PASS               two consecutive qualifying digests with Discord `collected`, no
#                          `output-too-large` on either row, and a non-zero GitHub Commits or
#                          Pull requests touched count across them (sweeper closes #9678)
#   1 = FAIL               a qualifying digest still carries `output-too-large` on Discord or GitHub
#   2 = NOT YET            the change has not reached main, or fewer than two qualifying digests exist
#   3 = CANNOT ESTABLISH   no qualifying digest 7 days after the change, or the clone cannot answer
#                          (shallow, or no history). A rejected draft publishes nothing, so absence
#                          is a signal: see the FAILED audit issue and the Sentry op
#                          `community-publication-rejected`.
#   4 = TRANSIENT          qualifying digests exist but are unrelated-bad (for example Discord
#                          `partial` for another cause): one such day must not file a false regression;
#                          past 14 days it becomes 3 (a standing unrelated-bad state is a finding)
#
# `--status-line` prints `discord=<status|none> github=<cause-or-status|none>` for the newest digest
# and always exits 0. It exists because preflight Check 10 runs the declared command on the PR branch
# (no cut-off yet) and treats a non-zero exit as a failed probe.
#
# Output is ENUM TOKENS ONLY: the sweeper posts the last 4 KB of this output on a public issue, so a
# digest line is never echoed. Test-only overrides (the sweeper runs under `env -i`, so they are never
# set in production): COLLECTOR_PROBE_DIGEST_DIR, COLLECTOR_PROBE_CUTOFF (epoch seconds),
# COLLECTOR_PROBE_NOW (epoch seconds).

set -uo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIGEST_DIR="${COLLECTOR_PROBE_DIGEST_DIR:-$ROOT/knowledge-base/support/community}"
HANDLER="apps/web-platform/server/inngest/functions/cron-community-monitor.ts"
MARKER="SOLEUR_COLLECTOR_COMPACT"
LAG_SECONDS=86400          # merge-to-deploy lag: a digest generated earlier is ignored, not a FAIL
ABSENCE_SECONDS=604800     # 7 days without a qualifying digest is itself a finding
UNGRADED_SECONDS=1209600   # 14 days of qualifying digests that never grade clean is a finding too

# Set by parse_row (printf -v); initialised here so no read is ever of an unset name.
d_status=none d_cause=none g_status=none g_cause=none g_line=""

# The closed vocabulary of failure causes (COMMUNITY_FAILURE_CAUSES in _cron-community-publication.ts).
is_known_cause() {
  case "$1" in auth|rate-limit|timeout|output-too-large|script-error|not-configured|unknown) return 0 ;; esac
  return 1
}

now_epoch() {
  if [[ "${COLLECTOR_PROBE_NOW:-}" =~ ^[0-9]+$ ]]; then printf '%s' "$COLLECTOR_PROBE_NOW"; else date -u +%s; fi
}

# Sets <prefix>_status and <prefix>_cause from a digest's `| <Platform> | <status> | ... |` row.
# Only enum tokens leave this function; the row text itself is never printed.
parse_row() { # $1=file $2=Platform $3=var prefix
  local file="$1" platform="$2" prefix="$3" line status cause=none
  line="$(grep -m1 -E "^\| ${platform} \| (collected|partial|failed|disabled) \|" "$file" 2>/dev/null || true)"
  if [[ -z "$line" ]]; then
    printf -v "${prefix}_status" '%s' none
    printf -v "${prefix}_cause" '%s' none
    [[ "$prefix" == g ]] && g_line=""
    return 0
  fi
  status="$(sed -E 's/^\| [A-Za-z]+ \| ([a-z]+) \|.*/\1/' <<<"$line")"
  if [[ "$line" == *output-too-large* ]]; then
    cause=output-too-large
  elif [[ "$status" == partial ]]; then
    # Renderer: `partial (<cause>; a 0 may mean unavailable): ...`
    cause="$(sed -nE 's/^[^|]*\|[^|]*\|[^|]*\| *partial \(([a-z-]+)[;)].*/\1/p' <<<"$line")"
    if [[ -z "$cause" ]] || ! is_known_cause "$cause"; then cause=unknown; fi
  elif [[ "$status" == failed ]]; then
    # Renderer: `collection failed: <cause>`
    cause="$(sed -nE 's/^[^|]*\|[^|]*\|[^|]*\| *collection failed: ([a-z-]+).*/\1/p' <<<"$line")"
    if [[ -z "$cause" ]] || ! is_known_cause "$cause"; then cause=unknown; fi
  fi
  printf -v "${prefix}_status" '%s' "$status"
  printf -v "${prefix}_cause" '%s' "$cause"
  [[ "$prefix" == g ]] && g_line="$line"
  return 0
}

# A digest is a regular, non-symlink file named <date>-digest.md. Prints its path, sorted by name.
list_digests() {
  local f
  for f in "$DIGEST_DIR"/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-digest.md; do
    [[ -f "$f" && ! -L "$f" ]] || continue
    printf '%s\n' "$f"
  done
}

generated_epoch() { # $1=file -> epoch of front-matter generated_at, or empty
  local ts
  ts="$(sed -nE '1,12s/^generated_at: ([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z)$/\1/p' "$1" 2>/dev/null | head -1)"
  [[ -n "$ts" ]] || return 0
  date -u -d "$ts" +%s 2>/dev/null || true
}

status_line() {
  local newest f
  f="$(list_digests | tail -1)"
  if [[ -n "$f" ]]; then
    parse_row "$f" Discord d
    parse_row "$f" GitHub g
  fi
  newest="${g_cause}"
  [[ "$newest" == none ]] && newest="$g_status"
  printf 'discord=%s github=%s\n' "$d_status" "$newest"
  exit 0
}

case "${1:-}" in
  --status-line) [[ $# -eq 1 ]] || { echo "NOT YET: unknown arguments" >&2; exit 2; }; status_line ;;
  "") ;;
  *) echo "NOT YET: unknown arguments" >&2; exit 2 ;;
esac

# --- Cut-off: the commit on main that introduced the flag in the handler. Fail closed. ---
if [[ "${COLLECTOR_PROBE_CUTOFF:-}" =~ ^[0-9]+$ ]]; then
  CUTOFF="$COLLECTOR_PROBE_CUTOFF"
else
  shallow="$(git -C "$ROOT" rev-parse --is-shallow-repository 2>/dev/null || echo unknown)"
  if [[ "$shallow" != false ]]; then
    echo "CANNOT ESTABLISH: the checkout is shallow or unreadable (shallow=${shallow}); the sweeper checks out full history"
    exit 3
  fi
  if ! git -C "$ROOT" rev-parse --verify -q origin/main >/dev/null 2>&1; then
    echo "CANNOT ESTABLISH: origin/main is not present in this checkout"
    exit 3
  fi
  CUTOFF="$(git -C "$ROOT" log --reverse -S"$MARKER" --format=%ct origin/main -- "$HANDLER" 2>/dev/null | head -1)"
  if [[ ! "$CUTOFF" =~ ^[0-9]+$ ]]; then
    echo "NOT YET: the compact-output flag has not reached origin/main"
    exit 2
  fi
fi

NOW="$(now_epoch)"
QUALIFY_AFTER=$((CUTOFF + LAG_SECONDS))

# --- Qualifying digests: generated after the cut-off plus the deploy lag. ---
declare -a QUAL=()
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  g="$(generated_epoch "$f")"
  [[ "$g" =~ ^[0-9]+$ ]] || continue
  if ((g > QUALIFY_AFTER)); then QUAL+=("$f"); fi
done < <(list_digests)

if ((${#QUAL[@]} == 0)); then
  if ((NOW > CUTOFF + ABSENCE_SECONDS)); then
    echo "CANNOT ESTABLISH: no digest generated after the change in 7 days; check the FAILED audit issue and the Sentry op community-publication-rejected"
    exit 3
  fi
  echo "NOT YET: no digest has been generated since the change"
  exit 2
fi

# FAIL: the NEWEST qualifying digest still reports the old cause on a platform the change targets.
# Only the newest: a digest generated between the merge and the deploy (the lag window is a
# heuristic) legitimately carries the old behaviour, and must not latch a permanent FAIL once
# later digests are clean.
NEWEST="${QUAL[${#QUAL[@]} - 1]}"
parse_row "$NEWEST" Discord d
parse_row "$NEWEST" GitHub g
if [[ "$d_cause" == output-too-large || "$g_cause" == output-too-large ]]; then
  name="$(basename "$NEWEST")"
  echo "FAIL: ${name:0:10} discord=${d_status}/${d_cause} github=${g_status}/${g_cause} (output-too-large persists)"
  exit 1
fi

if ((${#QUAL[@]} < 2)); then
  # The ungraded bound applies here too: one digest and then silence must not read as "NOT YET" forever.
  if ((NOW > CUTOFF + UNGRADED_SECONDS)); then
    echo "CANNOT ESTABLISH: only one qualifying digest 14 days after the change; check the FAILED audit issue and the Sentry op community-publication-rejected"
    exit 3
  fi
  echo "NOT YET: one qualifying digest so far (${#QUAL[@]} of 2 needed)"
  exit 2
fi

# PASS: the two newest qualifying digests have Discord collected, no output-too-large on either
# platform, and a non-zero GitHub count across them.
nonzero=no
ok=1
for f in "${QUAL[@]: -2}"; do
  parse_row "$f" Discord d
  parse_row "$f" GitHub g
  name="$(basename "$f")"
  [[ "$d_status" == collected ]] || ok=0
  [[ "$d_cause" == output-too-large || "$g_cause" == output-too-large ]] && ok=0
  commits="$(sed -nE 's/.*Commits ([0-9]+).*/\1/p' <<<"$g_line" | head -1)"
  prs="$(sed -nE 's/.*Pull requests touched ([0-9]+).*/\1/p' <<<"$g_line" | head -1)"
  if [[ "${commits:-0}" =~ ^[0-9]+$ && "${commits:-0}" -gt 0 ]] || [[ "${prs:-0}" =~ ^[0-9]+$ && "${prs:-0}" -gt 0 ]]; then nonzero=yes; fi
  echo "digest=${name:0:10} discord=${d_status}/${d_cause} github=${g_status}/${g_cause}"
done

if ((ok == 1)) && [[ "$nonzero" == yes ]]; then
  echo "PASS: two consecutive digests with Discord collected, no output-too-large, and measured GitHub counts (#9678)"
  exit 0
fi
# An unrelated-bad state must not read as reassurance forever: past the bound it is a finding.
if ((NOW > CUTOFF + UNGRADED_SECONDS)); then
  echo "CANNOT ESTABLISH: still not graded clean 14 days after the change (discord_ok=${ok} github_nonzero=${nonzero}); read the newest digests and the Sentry op collector-status-warn"
  exit 3
fi
echo "TRANSIENT: output-too-large is absent from the newest digest, but the digests do not yet show Discord collected with a non-zero GitHub count (discord_ok=${ok} github_nonzero=${nonzero})"
exit 4
