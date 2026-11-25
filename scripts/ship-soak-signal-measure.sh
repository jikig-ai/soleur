#!/usr/bin/env bash
# ship-soak-signal-measure.sh — scores a soak-signal matcher against REAL corpora.
#
# This exists because the first draft of the #7056 fix passed all 21 of its own
# acceptance criteria while silencing 28 of 50 real soak enrolments. It measured
# precision against a real corpus and recall against a phrase list it had written
# itself. The ground-truth positive set was one `grep` away and never used.
#
# So: AC1 (recall floor) and AC2 (precision ratio) are stated relative to the
# CURRENTLY-SHIPPED matcher, and both are measured here, in one run, over the
# same sets. A matcher that goes dark fails AC1 no matter how clean it looks.
#
# Ground truth (positives) = plans that actually enrol a follow-through probe.
#   grep -rlE 'scripts/followthroughs/[a-z0-9-]+\.sh' knowledge-base/project/plans/*.md
# This is a free, real, in-repo positive set: a plan that wires up a probe script
# has, by construction, a soak-gated close criterion for the gate to find.
#
# FP proxy (negatives-ish) = the N most recent plans by filename date. Not a true
# negative set — some genuinely declare soaks — which is exactly why AC2 is a
# BOUNDED RATIO with a non-zero floor (`new < old && new >= 1`) rather than an
# absolute count. Measured across six sliding windows the absolute number ranges
# 5-11, so any fixed threshold is a snapshot, not an invariant.
#
# Usage:
#   ship-soak-signal-measure.sh baseline            # the currently-shipped matcher
#   ship-soak-signal-measure.sh <path-to-scanner>   # any stdin->exit-0/1 scanner
#   ship-soak-signal-measure.sh both <path>         # both, side by side (AC1/AC2)
#
# A scanner reads a corpus on stdin and exits 0 when it signals, non-zero when it
# does not. `scripts/ship-soak-signal-gate.sh` is the shipped one.
set -uo pipefail

FP_WINDOW="${FP_WINDOW:-40}"

repo_root() { git rev-parse --show-toplevel; }

# The matcher exactly as it ships TODAY, for the relative baseline. Kept as a
# verbatim copy on purpose: this function must NOT track future edits to the
# gate, or the baseline drifts along with the thing it is the baseline for.
baseline_scan() {
  local corpus soak_re
  corpus="$(cat)"
  soak_re='soak|stays? (at )?(~?0|zero)|[0-9]+[- ]day[s]?( post-deploy| soak)|post-deploy (soak|verif|observ)|adopting[[:space:]]*(→|->|to)[[:space:]]*accepted|status[[:space:]]+flip'
  # Today's consumers fence-strip before matching; mirror that or the baseline
  # is measured against a pipeline nobody runs.
  local stripped
  stripped="$(printf '%s' "$corpus" | awk '
    /^```/ { in_fence = !in_fence; next }
    !in_fence { print }
    END { if (in_fence) exit 2 }
  ')" || stripped="$corpus"
  if LC_ALL=C.UTF-8 grep -qaiE "$soak_re" <<<"$stripped" 2>/dev/null \
     || grep -qaiE "$soak_re" <<<"$stripped" 2>/dev/null; then
    return 0
  fi
  return 1
}

# $1 = scanner spec ("baseline" or an executable path); stdin = corpus
run_scanner() {
  if [[ "$1" == "baseline" ]]; then
    baseline_scan
  else
    bash "$1" >/dev/null 2>&1
  fi
}

# $1 = scanner spec. Prints "<recall> <total> <fp> <fpwindow>".
score() {
  local scanner="$1" root gt_count=0 gt_hit=0 fp_count=0 fp_hit=0 f
  root="$(repo_root)"

  local -a ground_truth=()
  while IFS= read -r f; do
    [[ -n "$f" ]] && ground_truth+=("$f")
  done < <(grep -rlE 'scripts/followthroughs/[a-z0-9-]+\.sh' "$root"/knowledge-base/project/plans/*.md 2>/dev/null | sort)

  # A silently-empty ground-truth set would make recall vacuously perfect.
  if [[ ${#ground_truth[@]} -lt 1 ]]; then
    echo "FATAL: ground-truth positive set is empty — the corpus moved or the glob broke." >&2
    exit 2
  fi

  for f in "${ground_truth[@]}"; do
    gt_count=$((gt_count + 1))
    if run_scanner "$scanner" < "$f"; then gt_hit=$((gt_hit + 1)); fi
  done

  local -a recent=()
  while IFS= read -r f; do
    [[ -n "$f" ]] && recent+=("$f")
  done < <(find "$root/knowledge-base/project/plans" -maxdepth 1 -name '*.md' -print 2>/dev/null | sort -r | head -n "$FP_WINDOW")

  if [[ ${#recent[@]} -lt 1 ]]; then
    echo "FATAL: FP window is empty — the plans directory moved." >&2
    exit 2
  fi

  for f in "${recent[@]}"; do
    fp_count=$((fp_count + 1))
    if run_scanner "$scanner" < "$f"; then fp_hit=$((fp_hit + 1)); fi
  done

  echo "$gt_hit $gt_count $fp_hit $fp_count"
}

main() {
  case "${1:-}" in
    both)
      [[ -n "${2:-}" ]] || { echo "usage: $0 both <scanner-path>" >&2; exit 2; }
      read -r o_r o_t o_f o_w <<<"$(score baseline)"
      read -r n_r n_t n_f n_w <<<"$(score "$2")"
      printf 'design                recall            FP (window=%s)\n' "$o_w"
      printf 'shipped (baseline)    %s / %s          %s / %s\n' "$o_r" "$o_t" "$o_f" "$o_w"
      printf 'candidate             %s / %s          %s / %s\n' "$n_r" "$n_t" "$n_f" "$n_w"
      echo
      local ok=0
      # AC1: recall floor, relative. AC2: bounded ratio with a NON-ZERO floor —
      # the floor is what makes a dark gate fail rather than score perfectly.
      if [[ "$n_r" -ge $((o_r - 1)) ]]; then
        echo "AC1 recall floor  PASS  ($n_r >= $o_r - 1)"
      else
        echo "AC1 recall floor  FAIL  ($n_r < $o_r - 1) — the matcher went dark"; ok=1
      fi
      if [[ "$n_f" -lt "$o_f" && "$n_f" -ge 1 ]]; then
        echo "AC2 precision     PASS  ($n_f < $o_f and $n_f >= 1)"
      else
        echo "AC2 precision     FAIL  (need $n_f < $o_f and $n_f >= 1)"; ok=1
      fi
      exit "$ok"
      ;;
    "")
      echo "usage: $0 {baseline|<scanner-path>|both <scanner-path>}" >&2
      exit 2
      ;;
    *)
      read -r r t f w <<<"$(score "$1")"
      printf 'recall %s / %s    FP %s / %s\n' "$r" "$t" "$f" "$w"
      ;;
  esac
}

main "$@"
