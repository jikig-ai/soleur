#!/usr/bin/env bash
# Follow-through verification for #7556 — did the raised zot HTTP deadlines LAND, and did the
# deadline sub-mode STOP?
#
# WHY TWO SIGNALS AND NOT ONE. The change (#7555, ADR-190) is delivered by a `user_data` ForceNew
# replace, so "the config in the repo says 1800s" proves nothing about the running host. And a
# quiet log proves nothing either, because the failure is INTERMITTENT at roughly 1 in 13 — a
# window with zero failures is the expected outcome ~92% of the time even fully unfixed. So this
# probe requires BOTH:
#
#   (1) DELIVERY  — zot's own boot `configuration settings` line, on the NEWEST boot, reports both
#                   deadlines at the intended nanosecond value. This is zot reporting its own
#                   parsed config, not the repo describing itself.
#   (2) ABSENCE   — over a window long enough to matter, ZERO PatchBlobUpload rows carrying
#                   `i/o timeout` at `latency:1m0s`.
#
# Neither alone is a pass. (1) without (2) says the config landed and says nothing about effect;
# (2) without (1) is the ~92% coincidence above.
#
# ── SCOPED TO THE DEADLINE SUB-MODE, DELIBERATELY ──────────────────────────────────────────
# zot's `PatchBlobUpload` fails in at least TWO shapes. This probe grades only the `i/o timeout`
# at `latency:1m0s` shape — the deadline. `unexpected EOF` is a DIFFERENT sub-mode, observed
# during a run that SUCCEEDED, and it is explicitly out of scope for #7555. A PASS here is not
# evidence that EOF is gone, and the verdict text says so rather than leaving a reader to infer
# a broader claim from a green.
#
# ── WHAT THIS PROBE MUST NOT DO ────────────────────────────────────────────────────────────
# It must never report PASS for a state it could not establish. Every unestablished state is
# TRANSIENT (exit 2) with a distinct `reason=`, because this exit code auto-closes a tracker and
# "I could not tell" auto-closing a P1 follow-up is the failure this whole class exists to stop.
# `${VAR:?msg}` is BANNED here: under `set -u` it aborts with a bare bash diagnostic and no
# verdict line, which the sweeper records as an unclassified crash rather than a TRANSIENT.
#
# EXIT CONTRACT (the sweeper reads these numerically):
#   0  PASS       — window >= MIN_WINDOW_DAYS, >= MIN_SAMPLES on the newest boot, BOTH deadlines
#                   at DEADLINE_NS, and zero deadline-shaped PatchBlobUpload pairings.
#   1  FAIL       — a deadline is absent/wrong on the newest boot, OR a deadline-shaped failure
#                   was observed. Both are real findings about the running host.
#   2  TRANSIENT  — the state could not be established. Never a pass.
#
# Usage: bash scripts/followthroughs/zot-upload-ceiling-7556.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
QUERY="${ZOT_CEILING_QUERY:-${REPO_ROOT}/scripts/betterstack-query.sh}"
PARSE_LIB="${REPO_ROOT}/scripts/lib/zot-telemetry-parse.sh"

# The intended value, in the nanoseconds zot itself reports. Derived from the 1800s setting in
# cloud-init-registry.yml; if that setting changes, this must change with it and the ADR-190
# comment there is the single source for WHY the number is what it is.
DEADLINE_NS="${ZOT_CEILING_DEADLINE_NS:-1800000000000}"
WINDOW="${ZOT_CEILING_WINDOW:-7d}"
MIN_WINDOW_DAYS="${ZOT_CEILING_MIN_DAYS:-7}"
MIN_SAMPLES="${ZOT_CEILING_MIN_SAMPLES:-12}"

verdict() { echo "zot-upload-ceiling[#7556]: $1"; }

[[ -x "$QUERY" ]] || { verdict "TRANSIENT reason=query-not-executable"; echo "TRANSIENT: ${QUERY} is not executable."; exit 2; }
[[ -r "$PARSE_LIB" ]] || { verdict "TRANSIENT reason=parse-lib-unreadable"; echo "TRANSIENT: ${PARSE_LIB} is not readable — refusing to hand-roll the trusted-region parse."; exit 2; }
command -v python3 >/dev/null || { verdict "TRANSIENT reason=no-python3"; echo "TRANSIENT: python3 is not on PATH."; exit 2; }

# Window sanity BEFORE spending a query: a caller that shortens the window below the soak floor
# would otherwise get a PASS that means less than the contract advertises.
WIN_DAYS="$(printf '%s' "$WINDOW" | sed -n 's/^\([0-9][0-9]*\)d$/\1/p')"
if [[ -z "$WIN_DAYS" || "$WIN_DAYS" -lt "$MIN_WINDOW_DAYS" ]]; then
  verdict "TRANSIENT reason=window-too-short window=${WINDOW}"
  echo "TRANSIENT: the window must be >= ${MIN_WINDOW_DAYS}d for this verdict to mean anything."
  echo "  At the measured ~1-in-13 base rate, a short quiet window is the EXPECTED outcome even unfixed."
  exit 2
fi

qerr="$(mktemp)"
trap 'rm -f "$qerr"' EXIT INT TERM

# ── Signal 1: DELIVERY. zot's boot `configuration settings` line. ──────────────────────────
raw_cfg="$("$QUERY" --since "$WINDOW" --grep 'configuration settings' --limit 2000 2>"$qerr")"; crc=$?
if (( crc != 0 )); then
  verdict "TRANSIENT reason=query-failed-config query_rc=${crc}"
  echo "TRANSIENT: betterstack-query.sh exited ${crc}: $(head -c 400 "$qerr")"
  [[ "$crc" == "3" ]] && echo "  rc=3 is the credential guard — BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD} unset or EMPTY."
  echo "  NOT evidence about the registry host."
  exit 2
fi

cfg_rows="$(printf '%s\n' "$raw_cfg" | grep -c '[^[:space:]]' || true)"
if [[ "${cfg_rows:-0}" -eq 0 ]]; then
  verdict "TRANSIENT reason=no-config-line window=${WINDOW}"
  echo "TRANSIENT: no zot 'configuration settings' line in the window. The host may not have been"
  echo "  replaced yet, or the #7440 log channel is not delivering. Either way the DELIVERY half is"
  echo "  unestablished — an empty channel is not evidence the deadlines landed."
  exit 2
fi

# Both deadlines, read off the NEWEST such line. zot reports them as integer nanoseconds under
# the HTTP object, e.g. "ReadTimeout":1800000000000.
read_ns="$(printf '%s\n' "$raw_cfg" | grep -oE '"ReadTimeout":[0-9]+' | tail -1 | cut -d: -f2)"
write_ns="$(printf '%s\n' "$raw_cfg" | grep -oE '"WriteTimeout":[0-9]+' | tail -1 | cut -d: -f2)"

if [[ -z "$read_ns" || -z "$write_ns" ]]; then
  verdict "TRANSIENT reason=deadlines-unparseable read=${read_ns:-<none>} write=${write_ns:-<none>}"
  echo "TRANSIENT: a 'configuration settings' line exists but its ReadTimeout/WriteTimeout could not"
  echo "  be parsed. The line's shape may have changed across a zot bump — re-read it before trusting"
  echo "  any verdict here. NOT a pass and NOT a failure."
  exit 2
fi

if [[ "$read_ns" != "$DEADLINE_NS" || "$write_ns" != "$DEADLINE_NS" ]]; then
  verdict "FAIL reason=deadline-mismatch read_ns=${read_ns} write_ns=${write_ns} expected_ns=${DEADLINE_NS}"
  echo "FAIL: the running host does not carry the intended deadlines."
  echo "  Expected both at ${DEADLINE_NS} ns. If both read 60000000000, this host predates the"
  echo "  #7555 replace and the change has not been delivered — dispatch registry-host-replace."
  echo "  If exactly ONE matches, that is the Arm C split-brain ADR-190 exists to prevent."
  exit 1
fi

# ── Signal 2: ABSENCE of the deadline sub-mode. ────────────────────────────────────────────
raw_log="$("$QUERY" --since "$WINDOW" --grep 'PatchBlobUpload' --limit 5000 2>"$qerr")"; lrc=$?
if (( lrc != 0 )); then
  verdict "TRANSIENT reason=query-failed-log query_rc=${lrc}"
  echo "TRANSIENT: betterstack-query.sh exited ${lrc}: $(head -c 400 "$qerr")"
  echo "  The DELIVERY half passed, but absence was not established. NOT a pass."
  exit 2
fi

# SAMPLE FLOOR. A window with too few rows cannot support an absence claim: zero failures out of
# three uploads is not evidence. Counted over PatchBlobUpload rows of ANY shape — the denominator
# is "did uploads happen at all", not "did they fail".
patch_rows="$(printf '%s\n' "$raw_log" | grep -c 'PatchBlobUpload' || true)"
if [[ "${patch_rows:-0}" -lt "$MIN_SAMPLES" ]]; then
  verdict "TRANSIENT reason=too-few-samples patch_rows=${patch_rows:-0} min=${MIN_SAMPLES} window=${WINDOW}"
  echo "TRANSIENT: only ${patch_rows:-0} PatchBlobUpload rows in ${WINDOW}; need >= ${MIN_SAMPLES} before"
  echo "  an absence means anything. Too little upload traffic to conclude, NOT a clean run."
  exit 2
fi

# The deadline shape, both operands required. `i/o timeout` alone would also match a transient
# network fault; `latency:1m0s` alone would match any slow-but-successful request. The PAIRING is
# what identifies the 60 s deadline specifically — and after this fix a genuine 1800s cut would
# read `latency:30m0s`, so this pattern deliberately does NOT generalise to "any timeout".
deadline_hits="$(printf '%s\n' "$raw_log" | { grep 'PatchBlobUpload' || true; } | { grep -c 'i/o timeout' || true; })"
latency_hits="$(printf '%s\n' "$raw_log" | { grep 'PatchBlobUpload' || true; } | { grep -c 'latency:1m0s' || true; })"

if [[ "${deadline_hits:-0}" -gt 0 ]]; then
  verdict "FAIL reason=deadline-submode-present hits=${deadline_hits} latency_1m_hits=${latency_hits} window=${WINDOW}"
  echo "FAIL: ${deadline_hits} PatchBlobUpload row(s) carrying 'i/o timeout' in ${WINDOW}, on a host whose"
  echo "  deadlines DO read ${DEADLINE_NS} ns. The deadline was raised and uploads are still being cut,"
  echo "  so the ceiling is not the (only) constraint — re-open the diagnosis rather than raising the"
  echo "  number again. Read the paired HTTP-API row's Content-Length and latency for the new wall."
  exit 1
fi

verdict "PASS deadlines_ns=${DEADLINE_NS} patch_rows=${patch_rows} deadline_hits=0 window=${WINDOW}"
echo "PASS: both zot HTTP deadlines report ${DEADLINE_NS} ns on the running host, and across ${patch_rows}"
echo "  PatchBlobUpload rows in ${WINDOW} there are ZERO carrying 'i/o timeout'."
echo "  SCOPE: this grades the DEADLINE sub-mode only. 'unexpected EOF' is a separate shape, was"
echo "  observed during a SUCCESSFUL run, and is out of scope for #7555 — this PASS is not evidence"
echo "  about it. It is also not a claim that any particular release succeeded."
exit 0
