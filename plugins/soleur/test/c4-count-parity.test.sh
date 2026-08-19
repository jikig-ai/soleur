#!/usr/bin/env bash
# c4-count-parity.test.sh — CI parity gate for the counts hard-coded in model.c4 edge prose.
#
# model.c4 states exact counts in prose ("check-ins from 7 workflows", "Of 52 cron monitors",
# "one of ten Resend emitters"). Nothing checked them, so every new scheduled workflow or Resend
# emitter silently staled the architecture model — the counts were only ever corrected by hand,
# when someone happened to look. This asserts each one against its live derivation, so the
# addition itself fails loudly and names the edge to fix (#7160).
#
# Auto-discovered by the `scripts` group glob in scripts/test-all.sh (the
# `plugins/soleur/test/*.test.sh` loop) and run in the `test-scripts` CI shard, which rolls up
# into the required `test` check. Deliberately NOT placed in scripts/ — that directory is not
# auto-globbed and is policed only by an advisory job, so an unregistered suite there is the
# #5417 orphan class: green CI, zero coverage.
#
# DESIGN — two properties that are easy to get wrong and worth stating:
#
#  1. Every regex is CLAUSE-anchored, never a bare numeral (cq-assert-anchor-not-bare-token).
#     `grep -c '7'` in this file would match issue refs (#7138), ADR ordinals and ports. Spanning
#     the surrounding words also means a prose rewrite that DROPS a clause fails loudly rather
#     than passing vacuously, and each row asserts exactly-one cardinality so a duplicated clause
#     cannot silently resolve to whichever copy came first.
#  2. C1 and C5 are DIFFERENT derivations and must not be conflated. Seven FILES use the
#     heartbeat composite, but eight distinct monitor SLUGS check in from GitHub, because
#     scheduled-terraform-drift.yml declares two. A test deriving both from one command would
#     encode 7 == 8 and be wrong on its first run.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
MODEL_C4="$REPO_ROOT/knowledge-base/engineering/architecture/diagrams/model.c4"
WF_DIR="$REPO_ROOT/.github/workflows"
ACT_DIR="$REPO_ROOT/.github/actions"
MONITORS_TF="$REPO_ROOT/apps/web-platform/infra/sentry/cron-monitors.tf"

echo "=== C4 embedded-count parity (model.c4 prose vs live derivations) ==="
echo ""

assert_file_exists "$MODEL_C4" "model.c4 exists"
assert_file_exists "$MONITORS_TF" "cron-monitors.tf exists"
if [[ "$FAIL" -gt 0 ]]; then
  print_results
fi

# --- derivations -------------------------------------------------------------
# Each returns a single integer on stdout. Kept as functions so the failure message can print
# the derivation verbatim next to the mismatch.
#
# Every grep here carries `|| true`. This suite runs under `set -euo pipefail`, and grep exits 1
# on ZERO matches -- so without the guard a legitimately-zero derivation (someone deleted the
# last Resend emitter) would ABORT the script mid-run instead of reporting the mismatch. That
# still reds CI, but it reds it with no message at all, which is the case a parity gate most
# needs to explain. Measured, not assumed: dropping a guarded clause produced exactly that
# silent abort before these guards were added.

derive_heartbeat_workflows() {
  { grep -rlF 'actions/sentry-heartbeat' "$WF_DIR" || true; } | wc -l | tr -d ' '
}

derive_cron_monitors() {
  { grep -cF 'resource "sentry_cron_monitor"' "$MONITORS_TF" || true; } | head -1 | tr -d ' '
}

derive_github_slugs() {
  { grep -rhoE 'monitor-slug:[[:space:]]*[A-Za-z0-9_-]+' "$WF_DIR" || true; } \
    | sed -E 's/.*:[[:space:]]*//' | sort -u | grep -c . || true
}

derive_webapp_slugs() { echo $(( $(derive_cron_monitors) - $(derive_github_slugs) )); }

derive_resend_emitters() {
  { grep -rlE 'api\.resend\.com|notify-ops-email' "$WF_DIR" "$ACT_DIR" || true; } | wc -l | tr -d ' '
}

# Of the heartbeat-using workflows, split on whether the parsed `on:` declares a schedule.
# PyYAML parses an unquoted `on:` key as the BOOLEAN True, so `d.get("on")` silently yields
# 0 and 7 instead of 4 and 3. The d.get(True) fallback is load-bearing, not defensive.
derive_schedule_split() {  # <schedule|dispatch>
  python3 - "$WF_DIR" "$1" <<'PY'
import sys, os, yaml
wf_dir, want = sys.argv[1], sys.argv[2]
sched = disp = 0
for name in sorted(os.listdir(wf_dir)):
    if not name.endswith((".yml", ".yaml")):
        continue
    path = os.path.join(wf_dir, name)
    with open(path) as fh:
        text = fh.read()
    if "actions/sentry-heartbeat" not in text:
        continue
    doc = yaml.safe_load(text) or {}
    on = doc.get("on", doc.get(True))
    if isinstance(on, dict) and "schedule" in on:
        sched += 1
    else:
        disp += 1
print(sched if want == "schedule" else disp)
PY
}

derive_schedule_fired() { derive_schedule_split schedule; }
derive_dispatch_only() { derive_schedule_split dispatch; }

# --- number-word handling ----------------------------------------------------
# C7 is written as the WORD "ten", not a numeral, so a ([0-9]+) anchor cannot match it. Handled
# with an explicit word->int map rather than by rewriting the prose to a numeral: the prose reads
# better as English, and the map makes the choice visible instead of incidental.
word_to_int() {
  case "$1" in
    one) echo 1 ;; two) echo 2 ;; three) echo 3 ;; four) echo 4 ;; five) echo 5 ;;
    six) echo 6 ;; seven) echo 7 ;; eight) echo 8 ;; nine) echo 9 ;; ten) echo 10 ;;
    eleven) echo 11 ;; twelve) echo 12 ;;
    thirteen) echo 13 ;; fourteen) echo 14 ;; fifteen) echo 15 ;;
    *) echo "__UNMAPPED__" ;;
  esac
}

# --- the registry ------------------------------------------------------------
# id | edge | clause regex | mode (num|word) | derivation fn | human-readable derivation
REGISTRY=(
  "C1|github -> sentry|check-ins from [0-9]+ workflows|num|derive_heartbeat_workflows|grep -rlF 'actions/sentry-heartbeat' .github/workflows/ | wc -l"
  "C2|github -> sentry|[0-9]+ GHA-.schedule:.-fired|num|derive_schedule_fired|of the heartbeat workflows, those whose parsed on: has a schedule key"
  "C3|github -> sentry|and [0-9]+ .workflow_dispatch.-only|num|derive_dispatch_only|of the heartbeat workflows, those whose parsed on: has NO schedule key"
  "C4|github -> sentry|Of [0-9]+ cron monitors|num|derive_cron_monitors|grep -cF 'resource \"sentry_cron_monitor\"' apps/web-platform/infra/sentry/cron-monitors.tf"
  "C5|github -> sentry|[0-9]+ check in from here|num|derive_github_slugs|distinct monitor-slug: values across .github/workflows/"
  "C6|github -> sentry|and [0-9]+ from webapp|num|derive_webapp_slugs|C4 - C5 (monitors not checking in from GitHub)"
  "C7|github -> resend|one of [a-z]+ Resend emitters under [.]github/|word|derive_resend_emitters|grep -rlE 'api[.]resend[.]com|notify-ops-email' .github/workflows/ .github/actions/ | wc -l"
)

for row in "${REGISTRY[@]}"; do
  IFS='|' read -r id edge clause mode fn _ <<<"$row"
  # The human-readable derivation may itself contain '|', so take everything after the 5th
  # field rather than relying on read to have captured it whole.
  human="${row#*|*|*|*|*|}"

  # Cardinality first: exactly one clause match. Zero means the prose was rewritten and this row
  # is now guarding nothing; more than one means the extracted value is ambiguous.
  hits="$({ grep -oE "$clause" "$MODEL_C4" || true; } | wc -l | tr -d ' ')"
  if [[ "$hits" != "1" ]]; then
    echo "  FAIL: $id ($edge) clause matched $hits times, expected exactly 1" >&2
    echo "        clause: $clause" >&2
    echo "        A count guarded by a clause that no longer appears verbatim is guarding nothing." >&2
    echo "        fix:    re-anchor this row, or restore the clause in $MODEL_C4" >&2
    FAIL=$((FAIL + 1))
    continue
  fi

  matched="$({ grep -oE "$clause" "$MODEL_C4" || true; } | head -1)"
  if [[ "$mode" == "word" ]]; then
    raw="$(printf '%s' "$matched" | sed -E 's/^one of ([a-z]+) .*/\1/')"
    prose="$(word_to_int "$raw")"
    if [[ "$prose" == "__UNMAPPED__" ]]; then
      echo "  FAIL: $id ($edge) number-word \"$raw\" is not in the word->int map" >&2
      echo "        Add it to word_to_int, or rewrite the clause to a numeral." >&2
      FAIL=$((FAIL + 1))
      continue
    fi
  else
    prose="$({ printf '%s' "$matched" | grep -oE '[0-9]+' || true; } | head -1)"
  fi

  derived="$("$fn")"

  if [[ "$prose" == "$derived" ]]; then
    echo "  PASS: $id $edge — $matched (derived $derived)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: c4-count-parity: edge \`$edge\` is STALE ($id)" >&2
    echo "        clause:      \"$matched\"" >&2
    echo "        prose says:  $prose" >&2
    echo "        derived:     $derived" >&2
    echo "        derivation:  $human" >&2
    echo "        fix:         update knowledge-base/engineering/architecture/diagrams/model.c4," >&2
    echo "                     then run: bash scripts/regenerate-c4-model.sh" >&2
    FAIL=$((FAIL + 1))
  fi
done

# C1 and C5 must stay DIFFERENT derivations. If a future refactor makes them share one command
# this silently becomes an assertion that 7 == 8, so pin the invariant rather than the values.
c1="$(derive_heartbeat_workflows)"
c5="$(derive_github_slugs)"
if [[ "$c5" -ge "$c1" ]]; then
  echo "  PASS: C1 ($c1 files) and C5 ($c5 slugs) are derived independently, slugs >= files"
  PASS=$((PASS + 1))
else
  echo "  FAIL: C5 ($c5 distinct slugs) < C1 ($c1 heartbeat files) — impossible unless a" >&2
  echo "        derivation is globbing the wrong path; every file declares >= 1 slug." >&2
  FAIL=$((FAIL + 1))
fi

print_results
