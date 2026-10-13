#!/usr/bin/env bash
# ext-filter-detect.sh — SessionStart (matcher: startup|resume|clear|compact) external
# output-filter detector (#10230). Emits ONE JSON object on stdout — detected tools
# become newline-joined marker lines inside it (single-document stdout; sibling hooks
# all emit exactly one object):
#   {"systemMessage": "SOLEUR_EXT_FILTER tool=<t> version=<v> posture=<p>
#     via=path|settings-hook|proxy-env measured_at=<date|-> ref=known-external-tools"}
# and `SOLEUR_EXT_FILTER tool=none` when nothing is detected — so "hook dead" is
# distinguishable from "no filter" (the same liveness argument compaction-state.sh
# makes for SOLEUR_COMPACTION_SKIPPED). systemMessage costs zero model tokens; this is
# an operator-facing line, never additionalContext.
#
# Marker semantics (the marker is a per-session public claim — key=value only, never
# editorial prose; severity lives in docs/pages/known-external-tools.md):
#   posture=unmeasured             the divergence harness has NOT run against this tool
#                                  — explicitly not an assurance
#   posture=literal-clean          gate literals survived the divergence corpus (rtk, only
#                                  after the Phase-3 measurement lands — see POSTURE_RTK below)
#   posture=measured-incompatible  gate-literal divergence measured (headroom; only when the
#                                  detected version is <= the evaluated version and identity
#                                  is corroborated — never on a bare basename PATH hit, which
#                                  could be an unrelated `headroom`)
#   tool=proxy posture=unknown     ANTHROPIC_BASE_URL points at a non-default endpoint; a
#                                  generic proxy (LiteLLM/Helicone/corporate) must NEVER be
#                                  emitted under a vendor name
#   version=unknown                version probe failed -> posture floors at unmeasured
#
# Skips silently (exit 0, no output) when CLAUDE_PLUGIN_ROOT is unset, on the non-Claude
# harness markers version-banner.sh uses (CODEX_THREAD_ID, PLUGIN_ROOT), and when
# SOLEUR_DISABLE_EXT_FILTER_DETECT=1. The marker is Claude-Code-only by design — a Devin
# or other-harness session has no marker and that does NOT mean "no filter" (the doc's
# three-rung diagnostic has a manual path for those).
#
# Fails open: every path exits 0 and any error prints nothing. Plugin hooks are GLOBAL
# (they fire in every project), so a hook that errors or hangs would hit every session;
# the stdin read and every version probe are bounded.

[[ "${SOLEUR_DISABLE_EXT_FILTER_DETECT-}" == "1" ]] && exit 0
set -uo pipefail
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script emits marker text and -x would echo it (see #7797)\n' >&2; exit 78 ;;
esac
trap 'exit 0' EXIT

# --- posture constants (the Phase-3 conjunctive evidence gate flips POSTURE_RTK in the
# same commit that lands ext-filter-divergence-report.md; a failed or un-run gate keeps
# `unmeasured` — the marker never asserts an unmeasured claim) ---------------------------
POSTURE_RTK="unmeasured"            # -> "literal-clean" only after ext-filter-divergence.sh proves zero gate-literal divergence on an rtk-present host
POSTURE_HEADROOM="measured-incompatible"
HEADROOM_EVAL_VERSION="0.37.0"      # the measured ceiling: claims apply at or below this version
HEADROOM_MEASURED_AT="2026-09-07"   # archived eval date (specs/archive/…headroom-token-compression-eval)
RTK_MEASURED_AT="-"                 # the Phase-3 report's date once measured

trace() { [[ "${SOLEUR_HOOK_TRACE-}" == "1" ]] && printf 'ext-filter-detect: %s\n' "$*" >&2; return 0; }

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/ }"
  s="${s//$'\r'/ }"
  s="${s//$'\t'/ }"
  printf '%s' "$s"
}

MARKERS=()
emit() { # <marker fields...> -> append a marker line; flushed as ONE systemMessage object
  # (every sibling SessionStart hook emits a single JSON document; N top-level objects
  # risks first-object-only parsing dropping co-detection markers, or a plain-text
  # fallback landing them in model context — one object, newline-joined markers)
  MARKERS+=("SOLEUR_EXT_FILTER $*")
}

flush_markers() {
  ((${#MARKERS[@]})) || return 0
  local joined
  joined="$(printf '%s\n' "${MARKERS[@]}")"
  printf '{"systemMessage": "%s"}\n' "$(json_escape "$joined")"
}

# version_probe <tool> -> first token of `<tool> --version`, "unknown" on any failure.
version_probe() {
  local out
  out="$(timeout 2 "$1" --version 2>/dev/null | head -1 | awk '{print $NF}')"
  if [[ "$out" =~ ^v?[0-9]+\.[0-9]+ ]]; then printf '%s' "${out#v}"; else printf 'unknown'; fi
}

# ver_le a b -> 0 iff version a <= version b (dotted numerics). Pure bash — `sort -V`
# is GNU-only and its absence silently withholds a measured-incompatible warning.
ver_le() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+ ]] || return 1
  local a1 a2 a3 b1 b2 b3
  IFS=. read -r a1 a2 a3 <<<"$1"; IFS=. read -r b1 b2 b3 <<<"$2"
  a3="${a3%%[^0-9]*}"; b3="${b3%%[^0-9]*}"
  (( 10#${a1:-0} != 10#${b1:-0} )) && { (( 10#${a1:-0} < 10#${b1:-0} )); return; }
  (( 10#${a2:-0} != 10#${b2:-0} )) && { (( 10#${a2:-0} < 10#${b2:-0} )); return; }
  (( 10#${a3:-0} <= 10#${b3:-0} ))
}

# settings_hit <tool> -> prints the tilde-collapsed settings file that wires <tool> into
# Claude hooks (a PreToolUse/hook entry naming it), or nothing. HOME- and cwd-level files.
settings_hit() {
  local tool="$1" f
  for f in "${HOME:-}/.claude/settings.json" "${HOME:-}/.claude/settings.local.json" \
           "${CWD_CLAUDE:-}/settings.json" "${CWD_CLAUDE:-}/settings.local.json"; do
    [[ -r "$f" ]] || continue
    if grep -l '"hooks"' "$f" >/dev/null 2>&1 && grep -l "$tool" "$f" >/dev/null 2>&1; then
      case "$f" in "$HOME"/*) printf '~%s' "${f#"$HOME"}" ;; *) printf '%s' "$f" ;; esac
      return 0
    fi
  done
  return 1
}

CWD_CLAUDE=""
main() {
  [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]] || return 0
  [[ -n "${CODEX_THREAD_ID:-}" || -n "${PLUGIN_ROOT:-}" ]] && return 0
  if [[ "${1:-}" == "--self-test" ]]; then shift; fi

  # Bounded stdin read for the envelope's cwd (a hook that hangs at SessionStart is worse
  # than a crashed one — compaction-state.sh:123-129). Absent or malformed: no cwd arm.
  local in=""
  in="$(timeout 5 cat 2>/dev/null || true)"
  local cwd
  cwd="$(printf '%s' "$in" | grep -o '"cwd"[^,}]*' | head -1 | cut -d'"' -f4)"
  [[ -d "$cwd/.claude" ]] && CWD_CLAUDE="$cwd/.claude"
  trace "cwd=$cwd CWD_CLAUDE=$CWD_CLAUDE"

  local found=0 tool ver via posture m_at s_hit

  # --- proxy arm: a non-default ANTHROPIC_BASE_URL emits the NEUTRAL marker, never a
  # named vendor claim — a LiteLLM/Helicone/corporate proxy is the user's own infra.
  case "${ANTHROPIC_BASE_URL:-}" in
    ""|https://api.anthropic.com|https://api.anthropic.com/) : ;;
    *) emit "tool=proxy posture=unknown via=proxy-env measured_at=- ref=known-external-tools"; found=1 ;;
  esac

  for tool in rtk headroom; do
    via=""; s_hit=""
    command -v "$tool" >/dev/null 2>&1 && via="path"
    s_hit="$(settings_hit "$tool")" && via="${via:+$via,}settings-hook"
    [[ -n "$via" ]] || continue
    found=1
    ver="$(version_probe "$tool")"
    case "$tool" in
      rtk)
        # a named posture requires corroboration AND a resolved version; a bare PATH
        # basename hit is unmeasured by construction.
        if [[ "$via" == *settings-hook* && "$ver" != unknown ]]; then posture="$POSTURE_RTK"; else posture="unmeasured"; fi
        m_at="$RTK_MEASURED_AT" ;;
      headroom)
        if [[ "$via" == *settings-hook* && "$ver" != unknown ]] && ver_le "$ver" "$HEADROOM_EVAL_VERSION"; then
          posture="$POSTURE_HEADROOM"; m_at="$HEADROOM_MEASURED_AT"
        else
          posture="unmeasured"; m_at="$HEADROOM_MEASURED_AT"
        fi ;;
    esac
    emit "tool=$tool version=$ver posture=$posture via=$via measured_at=$m_at${s_hit:+ path=$s_hit} ref=known-external-tools"
  done

  (( found )) || emit "tool=none"
  flush_markers
  return 0
}

main "$@"
