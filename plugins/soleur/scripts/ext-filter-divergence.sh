#!/usr/bin/env bash
# ext-filter-divergence.sh — measures whether an external output filter (rtk) preserves the
# literal strings Soleur's evidence gates read (#10230). For each corpus command, capture
# the VERBATIM output and the FILTERED output, then count preservation of the gate-literal
# set: file.ext:line citations, SHA/#PR references, SOLEUR_* markers, eval-gate:block,
# [id: ...] anchors, gh --json field names, git porcelain rows, pipeline-tally fields, and
# SOLEUR_* env echoes.
#
# Three arms:
#   CONTROL (head -3): deliberately lossy, runs UNCONDITIONALLY and MUST report divergence —
#     zero control divergence means the instrument itself is dead: exit non-zero with
#     INSTRUMENT-DEFECT (an instrument that cannot see loss must not certify compatibility;
#     the "un-run instrument" class, learnings/2026-09-07).
#   RTK: verbatim vs `rtk <cmd>` — skips ONLY when `command -v rtk` fails, reporting
#     SKIPPED reason=rtk-absent with exit 0 (the measurement then stays unmeasured).
#   GRAMMAR-DRIFT (non-fatal): on the rtk-present arm, scrape `rtk --help` for the canonical
#     exec-subcommand set and warn when it disagrees with
#     scripts/lib/ext-filter-grammar.tsv — upstream added a shape we don't unwrap.
#
# Pass condition (conjunctive — both required before `literal-clean` may be asserted):
#   rtk-arm divergence == 0  AND  control-arm divergence > 0.
# Any other outcome leaves the posture at `unmeasured`.
#
# Corpus rules (scripts/ext-filter-divergence-corpus.txt, one command per line, # comments):
# every command is READ-ONLY, deterministic, offline (no network/auth — an unauthed gh call
# fails identically on both arms and measures nothing), and emits MORE than 3 lines so the
# head -3 control can actually diverge.
#
# Output: a markdown divergence report on stdout, intended to land at
#   knowledge-base/project/specs/feat-fcc-token-optimizations/ext-filter-divergence-report.md
# Usage: ext-filter-divergence.sh [--corpus <file>] [--report <file>]

set -uo pipefail
trap 'exit 0' EXIT   # never take down a caller; report SKIPPED/INSTRUMENT-DEFECT on stdout

CORPUS="${CORPUS:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ext-filter-divergence-corpus.txt}"
REPORT=""
while (( $# )); do
  case "$1" in
    --corpus) CORPUS="$2"; shift 2 ;;
    --report) REPORT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

CANON="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/ext-filter-grammar.tsv"
WORK="$(mktemp -d -t extdiv.XXXXXXXX)" || exit 3
trap 'rm -rf "$WORK"' EXIT INT TERM HUP

# the gate-literal classes, as EREs over command output. One grep per class per output file;
# a class counts preserved iff EVERY occurrence in the verbatim output also appears in the
# filtered output (line-level set inclusion, not just presence).
LITERAL_CLASSES=(
  'file-line-citation:[A-Za-z0-9_./-]+\.[a-zA-Z0-9]+:[0-9]+'
  'sha-or-pr-ref:([0-9a-f]{7,40}\b|#[0-9]{2,})'
  'soleur-marker:SOLEUR_[A-Z_]+'
  'eval-gate-marker:eval-gate:(block|pass|ask)'
  'rule-id-anchor:\[id: [a-z0-9-]+\]'
  'gh-json-field:"(title|number|state|labels?|body|url)":'
  'porcelain-row:^( M|\?\?|M |A |D )'
  'tally-field:[a-z_]+=[0-9]+( |$)'
  'soleur-env-echo:^SOLEUR_[A-Z_]+='
)

extract_literals() { # <class ERE> <output file> -> sorted unique literal LINES containing the class
  grep -nE "$1" "$2" 2>/dev/null | sed 's/^[0-9]*://' | sort -u
}

divergence_count() { # <verbatim file> <filtered file> -> count of gate-literal lines lost + classes touched
  local v="$1" f="$2" lost=0 cls
  for entry in "${LITERAL_CLASSES[@]}"; do
    cls="${entry%%:*}"; ere="${entry#*:}"
    comm -23 <(extract_literals "$ere" "$v") <(extract_literals "$ere" "$f") > "$WORK/lost.$$" 2>/dev/null || continue
    n="$(wc -l < "$WORK/lost.$$" | tr -d ' ')"
    if (( n > 0 )); then
      lost=$((lost + n))
      printf '%s\n' "$cls" >> "$WORK/classes.$$"
      sed 's/^/    LOST /' "$WORK/lost.$$" >> "$WORK/detail.$$"
    fi
  done
  printf '%s' "$lost"
}

declare -A LOST_CLASSES=()
run_arm() { # <name> <runner> -> sets ARM_LOST ARM_RUN
  local name="$1" runner="$2" cmd i=0 lost_total=0
  : > "$WORK/detail.$$"
  while IFS= read -r cmd; do
    [[ -z "${cmd// /}" || "$cmd" == \#* ]] && continue
    i=$((i + 1))
    bash -c "$cmd" > "$WORK/verb.$$" 2>/dev/null || true
    eval "$runner" > "$WORK/filt.$$" 2>/dev/null || true
    n="$(divergence_count "$WORK/verb.$$" "$WORK/filt.$$")"
    lost_total=$((lost_total + n))
    printf '    %s %02d lost=%d :: %s\n' "$name" "$i" "$n" "$cmd" >> "$WORK/armrows.$$"
  done < "$CORPUS"
  ARM_LOST="$lost_total"; ARM_RUN="$i"
  ARM_CLASSES="$(sort -u "$WORK/classes.$$" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
}

emit() { printf '%s\n' "$*"; }

# --- run ---------------------------------------------------------------------
: > "$WORK/armrows.$$"; : > "$WORK/classes.$$"
control_lost=0; control_run=0
run_arm "CONTROL" 'bash -c "$cmd" | head -3'
control_lost="$ARM_LOST"; control_run="$ARM_RUN"
CONTROL_CLASSES="$ARM_CLASSES"

rtk_status=""; rtk_lost=0; rtk_run=0; grammar_note=""
if command -v rtk >/dev/null 2>&1; then
  : > "$WORK/armrows.$$"; : > "$WORK/classes.$$"
  run_arm "RTK" 'rtk $cmd'
  rtk_lost="$ARM_LOST"; rtk_run="$ARM_RUN"
  RTK_CLASSES="$ARM_CLASSES"
  rtk_status="measured"

  # grammar-drift canary: exec subcommands rtk advertises vs the canonical set
  canon_set="$(awk -F'\t' '$0 !~ /^#/ && NF >= 3 && $2 == "exec" { print $1 }' "$CANON" 2>/dev/null | sort | tr '\n' ' ' | sed 's/ $//')"
  help_set=""
  for sub in run err test proxy bypass summary gain session discover init telemetry config env smart deps json pipe; do
    rtk "$sub" --help >/dev/null 2>&1 && help_set="$help_set $sub"
  done
  if [[ -n "$canon_set" ]]; then
    drift="$(comm -23 <(printf '%s\n' $canon_set | sort) <(printf '%s\n' $help_set | sort) | tr '\n' ' ')"
    newexec="$(comm -13 <(printf '%s\n' $canon_set | sort) <(printf '%s\n' $help_set | sort) | tr '\n' ' ')"
    [[ -n "${drift// /}${newexec// /}" ]] && grammar_note="GRAMMAR-DRIFT missing=(${drift% }) new=(${newexec% }) vs canonical ($canon_set)"
  fi
else
  rtk_status="SKIPPED reason=rtk-absent"
fi

# --- verdict -----------------------------------------------------------------
verdict="INSTRUMENT-DEFECT"
if (( control_lost == 0 )); then
  verdict="INSTRUMENT-DEFECT: control arm reported zero divergence (the instrument cannot see loss — no result is credible)"
elif [[ "$rtk_status" == SKIPPED* ]]; then
  verdict="UNMEASURED: rtk absent; control arm alive (lost=$control_lost) — posture stays unmeasured"
elif (( rtk_lost == 0 )); then
  verdict="LITERAL-CLEAN: rtk-arm divergence zero on $rtk_run corpus commands (control lost=$control_lost — instrument alive)"
else
  verdict="DIVERGENT: rtk-arm lost $rtk_lost gate-literal lines on $rtk_run corpus commands — posture stays unmeasured"
fi

{
  emit "# ext-filter divergence report — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  emit ""
  emit "- host: $(uname -srm | cut -d' ' -f1-3)"
  emit "- rtk: $(command -v rtk >/dev/null 2>&1 && rtk --version 2>/dev/null | head -1 || echo absent)"
  emit "- corpus: $CORPUS ($control_run commands)"
  emit ""
  emit "## Verdict"
  emit ""
  emit "**$verdict**"
  [[ -n "$grammar_note" ]] && emit "" && emit "**$grammar_note**"
  emit ""
  emit "## Arms"
  emit ""
  emit "| arm | commands | gate-literal lines lost | classes touched |"
  emit "|---|---|---|---|"
  emit "| control (head -3, must diverge) | $control_run | $control_lost | ${CONTROL_CLASSES:-—} |"
  emit "| rtk | ${rtk_run:-0} | ${rtk_lost:-0} | ${RTK_CLASSES:---} |"
  emit ""
  emit "## Per-command detail"
  emit ""
  cat "$WORK/armrows.$$" 2>/dev/null
  emit ""
  emit "## Lost literals (control arm proves the detector sees each class)"
  emit ""
  cat "$WORK/detail.$$" 2>/dev/null | sort -u | head -50
} > "$WORK/report.md"

if [[ -n "$REPORT" ]]; then cp "$WORK/report.md" "$REPORT"; fi
cat "$WORK/report.md"

if [[ "$verdict" == INSTRUMENT-DEFECT* ]]; then exit 4; fi
[[ "$verdict" == DIVERGENT* ]] && exit 1
exit 0
