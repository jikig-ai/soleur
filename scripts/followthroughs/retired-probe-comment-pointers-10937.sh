#!/usr/bin/env bash
# Follow-through verification: the retired-probe comment pointers in cat-deploy-state.sh are gone (G1 PR-4a, #10937).
#
# Exit semantics (scripts/sweep-followthroughs.sh): 0 = PASS (the stale pointers are gone; the tracker closes),
# 2 = NOT YET (a comment still names a retired probe), anything else = TRANSIENT.

set -uo pipefail

case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this probe runs inside the sweeper where -x output is posted to a public issue (see #7797)\n' >&2; exit 78 ;;
esac

# soleur:followthrough-stub v1

FILE="apps/web-platform/infra/cat-deploy-state.sh"
[[ -f "$FILE" ]] || { echo "TRANSIENT: $FILE not found in the checkout"; exit 1; }

# grep -c prints the count even at zero (rc 1 = no match); rc >= 2 is a real read failure.
hits="$(grep -cE 'canary-promotion-5875|workspace-isolation-verdict-2640' "$FILE")"; rc=$?
if (( rc >= 2 )); then echo "TRANSIENT: could not read $FILE (grep rc=$rc)"; exit 1; fi
if (( hits > 0 )); then
  echo "NOT YET: $FILE still has $hits comment line(s) naming a retired followthrough probe"
  exit 2
fi
echo "PASS: no comment in $FILE names a retired followthrough probe"
exit 0
