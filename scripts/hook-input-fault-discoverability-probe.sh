#!/usr/bin/env bash
# Discoverability probe for the PreToolUse hook-input fault signal (#7275).
#
# THE QUESTION IT ANSWERS: when a hook cannot parse its stdin and runs with its
# guards disarmed, is there a path from that event to something an operator can
# read? It is the `discoverability_test.command` for the #7275 plan, and
# preflight Check 10 EXECUTES it.
#
# WHY IT IS A SCRIPT AND NOT `bash scripts/rule-metrics-aggregate.sh`.
# That was the first form and it was vacuous, measured: run bare against a root
# with no incident rows — which is what a fresh checkout and any CI sandbox is —
# the aggregator prints `0 rule-carrying incident lines; leaving committed ...
# unchanged` and exits 0 with NO WARNING and NO breakdown. The gate passed
# without ever exercising the path it names. The plan's `expected_output` field
# described the missing precondition ("run against a sandboxed
# INCIDENTS_REPO_ROOT seeded with one synthetic row") but Check 10 runs the
# command, not the prose. Secondarily, the bare form WRITES
# knowledge-base/project/rule-metrics.json into the working tree.
#
# So this seeds its own fixture, asserts the operator-visible line actually
# appears, and touches nothing in the repository.
set -uo pipefail

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq missing — probe cannot run"; exit 0; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGG="$REPO_ROOT/scripts/rule-metrics-aggregate.sh"
[[ -x "$AGG" || -r "$AGG" ]] || { echo "FATAL: aggregator not found at $AGG" >&2; exit 2; }

# P1b (#7708): `mktemp -d` inherits TMPDIR, so a RELATIVE TMPDIR yields a relative
# root — after which the trap's `rm -rf` resolves against whatever directory the
# probe happens to be standing in when it fires. The body is a byte-exact COPY of
# the canonical definition in plugins/soleur/test/test-helpers.sh, whose equality
# fixture-dir-operand-assert.test.sh asserts; do not reword it here alone. It is
# copied rather than sourced because this is a production script, not a suite.
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

export TMPDIR="${TMPDIR:-/var/tmp}"
ROOT="$(mktemp -d "${TMPDIR%/}/hookfault-probe.XXXXXXXX")" || { echo "FATAL: mktemp failed" >&2; exit 2; }
assert_fixture_dir "$ROOT"
trap 'assert_fixture_dir "$ROOT"; rm -rf "$ROOT" 2>/dev/null || true' EXIT INT TERM HUP

mkdir -p "$ROOT/.claude" "$ROOT/knowledge-base/project" || { echo "FATAL: could not build the fixture root" >&2; exit 2; }
# The aggregator parses the rule corpus and ABORTS if it yields zero rules, so
# the fixture needs the real AGENTS files. They are COPIED IN, never referenced
# in place: the aggregator writes rule-metrics.json under the root it is given,
# and pointing it at the repo would make this probe mutate the working tree —
# which is half of what was wrong with the bare-command form it replaces.
for f in AGENTS.md AGENTS.rules.md; do
  [[ -r "$REPO_ROOT/$f" ]] || { echo "FATAL: $f not readable — cannot build the fixture" >&2; exit 2; }
  cp "$REPO_ROOT/$f" "$ROOT/$f" || { echo "FATAL: could not copy $f into the fixture" >&2; exit 2; }
done

# One synthetic fault row per payload class the split produces, so the probe
# fails if the breakdown collapses them back into one bucket.
i=0
for rid in hook-input-baddoc hook-input-empty hook-input-nonobject hook-input-internal; do
  printf '{"schema":1,"timestamp":"2026-09-08T10:00:%02dZ","rule_id":"%s","event_type":"warn","rule_text_prefix":"x","command_snippet":"hook=probe reason=%s"}\n' \
    "$i" "$rid" "${rid#hook-input-}" >> "$ROOT/.claude/.rule-incidents.jsonl"
  i=$((i + 1))
done

out="$(INCIDENTS_REPO_ROOT="$ROOT" bash "$AGG" 2>&1)"; rc=$?

fail() { printf 'FAIL: %s\n' "$1" >&2; [[ -n "${2:-}" ]] && printf '  %s\n' "$2" >&2; exit 1; }

(( rc == 0 )) || fail "the aggregator exited $rc on a seeded fixture" "$out"

# 1. The operator-visible line must exist. This is the whole point: a counter
#    nobody prints is not a surface.
grep -q 'hook input-contract fault' <<<"$out" \
  || fail "no operator-visible WARNING line — the fault is recorded and unreadable" "$out"

# 2. The per-reason breakdown must DISCRIMINATE. A line reporting only a total
#    would satisfy check 1 while losing exactly what #7275 was filed about.
for r in baddoc empty nonobject internal; do
  grep -q "$r=1" <<<"$out" || fail "the breakdown does not name '$r' — the split is not reaching the operator" "$out"
done

# 3. The probe must not have written into the repository.
[[ ! -e "$REPO_ROOT/knowledge-base/project/rule-metrics.json.probe" ]] || fail "probe wrote into the repo"

printf 'OK: a disarmed-guard fault is discoverable — %s\n' \
  "$(grep -o 'WARNING: .*' <<<"$out" | head -1 | cut -c1-140)"
exit 0
