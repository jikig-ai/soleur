#!/usr/bin/env bash
# Follow-through: the sentry fidelity probe's output is `cat`-ed raw into the
# Actions log by scheduled-sentry-alert-drift.yml and apply-sentry-infra.yml, and a
# vendor-controlled live name may carry a legacy `##[cmd]` runner command, which the
# runner is recorded (scheduled-prod-version-drift.yml) to match anywhere in a line.
# PASS once either fix has landed: the probe's jq `safe` rewrites `##[`, or the
# drift workflow wraps the probe output in `::stop-commands::`.
#
# Exit semantics (scripts/sweep-followthroughs.sh): 0 PASS, 1 FAIL, other TRANSIENT.
# Convention: knowledge-base/engineering/operations/runbooks/followthrough-convention.md
set -uo pipefail
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace (see #7797)\n' >&2; exit 78 ;;
esac

# soleur:followthrough-stub v1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" || exit 2
PROBE="$ROOT/scripts/sentry-alert-live-fidelity.sh"
WF="$ROOT/.github/workflows/scheduled-sentry-alert-drift.yml"
[[ -r "$PROBE" && -r "$WF" ]] || exit 2

if grep -qF 'stop-commands' "$WF"; then
  echo "PASS: the drift workflow wraps the probe output in ::stop-commands::"
  exit 0
fi
if grep -E "^SAFE_JQ=" "$PROBE" | grep -qF '##\\['; then
  echo "PASS: the probe's safe() rewrites legacy ##[ runner commands"
  exit 0
fi
echo "FAIL: neither ::stop-commands:: around the drift workflow's probe output nor a ##[ rewrite in SAFE_JQ is present"
exit 1
