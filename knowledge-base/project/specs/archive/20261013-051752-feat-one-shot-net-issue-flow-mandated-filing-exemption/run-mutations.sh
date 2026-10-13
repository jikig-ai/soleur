#!/usr/bin/env bash
# Mutation battery for the net-issue-flow mandated-filing exemption.
#
# A gate's vacuities fail OPEN, so "the suite is green" is worth nothing until
# each assertion is shown to be CAPABLE of going red. Mutation definitions live
# in mutations.py (plain Python strings — building them through nested shell
# quoting produced 6 spurious BROKEN results on the first attempt).
#
# Three outcomes, deliberately distinct:
#   killed    — mutation applied, suite went RED. The assertion is real.
#   SURVIVED  — mutation applied, suite stayed GREEN. The assertion is vacuous.
#   BROKEN    — the harness could not set up, or the anchor was absent. NOT a
#               verdict about the SUT: a harness that could not write a file
#               reporting "the guard did not detect this" is the worst outcome
#               available, because it reads as a clean result.
#
# ONE sandbox, reused with per-file restore. A per-mutation `cp -a` of the repo
# copies 2.3 GB of node_modules 26 times (~65 GB of I/O) and does not finish.
set -uo pipefail
export LC_ALL=C
# /tmp is a machine-global tmpfs shared with sibling worktrees; a full /tmp turns
# setup failures into phantom SURVIVED verdicts.
export TMPDIR="${TMPDIR:-/var/tmp}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../../.." && pwd)"
MUT_PY="$HERE/mutations.py"
TEST_REL="plugins/soleur/test/net-issue-flow.test.sh"
HOOK_TEST_REL=".claude/hooks/ship-net-issue-flow-gate.test.sh"

SB="$(mktemp -d -t nif-mut.XXXXXXXX)" || { echo "FATAL: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$SB"' EXIT

echo "=== building sandbox (excluding node_modules/.git) ==="
if ! rsync -a --exclude '.git' --exclude 'node_modules' --exclude '.worktrees' \
     --exclude '_site' --exclude '.next' "$REPO/" "$SB/" 2>/dev/null; then
  echo "FATAL: sandbox build failed" >&2; exit 2
fi
# The suites shell out to real git for `rev-parse --show-toplevel`; give the
# sandbox its own repo so it can never reach back into the working tree.
( cd "$SB" && git init -q -b main && git add -A >/dev/null 2>&1 \
    && git -c user.email=t@t -c user.name=t commit -qm sandbox >/dev/null 2>&1 ) || true
echo "  ok  sandbox at $SB"

echo
echo "=== baseline (both suites must be GREEN, or every verdict below is noise) ==="
( cd "$SB" && bash "$TEST_REL" ) >"$SB/.base1" 2>&1 \
  && echo "  ok  gate suite green" \
  || { echo "  FATAL: baseline gate suite RED in sandbox"; tail -5 "$SB/.base1"; exit 2; }
( cd "$SB" && bash "$HOOK_TEST_REL" ) >"$SB/.base2" 2>&1 \
  && echo "  ok  hook suite green" \
  || { echo "  FATAL: baseline hook suite RED in sandbox"; tail -5 "$SB/.base2"; exit 2; }
echo

killed=0; surv=0; broken=0; n=0
while IFS=$'\t' read -r name rel testrel; do
  [[ -z "$name" ]] && continue
  n=$((n + 1))

  cp -a "$SB/$rel" "$SB/.pristine" 2>/dev/null || {
    printf '  BROKEN   %-56s (backup failed)\n' "$name"; broken=$((broken + 1)); continue; }

  if ! python3 "$MUT_PY" "$SB" "$name" 2>"$SB/.muterr"; then
    printf '  BROKEN   %-56s (%s)\n' "$name" "$(tr -d '\n' < "$SB/.muterr" | cut -c1-58)"
    broken=$((broken + 1)); cp -a "$SB/.pristine" "$SB/$rel"; continue
  fi
  if diff -q "$SB/.pristine" "$SB/$rel" >/dev/null 2>&1; then
    printf '  BROKEN   %-56s (mutation did not land)\n' "$name"
    broken=$((broken + 1)); cp -a "$SB/.pristine" "$SB/$rel"; continue
  fi

  ( cd "$SB" && bash "$testrel" ) >"$SB/.out" 2>&1
  rc=$?
  cp -a "$SB/.pristine" "$SB/$rel"

  if [[ "$rc" -ne 0 ]]; then
    printf '  killed   %-56s\n' "$name"; killed=$((killed + 1))
  else
    printf '  SURVIVED %-56s <-- VACUOUS\n' "$name"; surv=$((surv + 1))
  fi
done < <(python3 "$MUT_PY" --list)

# Restoring after every case is only trustworthy if the tree really is pristine
# at the end; otherwise a late "killed" could be an artifact of an earlier
# mutation that never got rolled back.
echo
if diff -q "$REPO/$TEST_REL" "$SB/$TEST_REL" >/dev/null 2>&1 \
  && diff -q "$REPO/plugins/soleur/skills/ship/scripts/net-issue-flow.sh" \
             "$SB/plugins/soleur/skills/ship/scripts/net-issue-flow.sh" >/dev/null 2>&1; then
  echo "  ok  sandbox restored to pristine after the run"
else
  echo "  BROKEN sandbox did not restore — verdicts above may be contaminated"
  broken=$((broken + 1))
fi

printf '=== %d mutations: killed=%d survived=%d broken=%d ===\n' "$n" "$killed" "$surv" "$broken"
[[ "$n" -ge 37 ]] || { echo "FATAL: mutation list truncated (expected >=37)" >&2; exit 2; }
[[ "$surv" -eq 0 && "$broken" -eq 0 ]] || exit 1
