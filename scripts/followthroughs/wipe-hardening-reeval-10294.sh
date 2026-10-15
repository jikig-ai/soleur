#!/usr/bin/env bash
# wipe-hardening-reeval-10294.sh -- date-trigger re-evaluation for the three hardening items the review of
# PR #10294 (the wipe body for #10138) filed as a scope-out: delete_protection on the live LUKS volume, a
# self-review control on the web-platform-infra-apply environment, and the bootstrap listing blind spots.
#
# DATE trigger: the directive's `earliest=` gate (2026-10-24, the open CLO re-ruling date, #9066) is the whole
# check; the body is a trivial exit 0 by the convention. PASS closes the tracker, so the PASS text says which
# boxes of the issue are still open: closing the tracker must not drop them.
#
# RETIREMENT: delete this file when the tracking issue closes (`git grep wipe-hardening-reeval` finds only the
# issue directive and this file).
#
# Exit semantics (enforced by scripts/sweep-followthroughs.sh):
#   0 = PASS         (close-criteria met; sweeper closes the issue)
#   1 = FAIL         (criteria not met; sweeper comments, leaves open)
#   * = TRANSIENT    (network error, unexpected state; sweeper retries next sweep)
#
# Required secrets: declare via the directive `secrets=` clause AND add to
# .github/workflows/scheduled-followthrough-sweeper.yml env: block.
#
# Convention: knowledge-base/engineering/operations/runbooks/followthrough-convention.md

set -uo pipefail

# REFUSE TO RUN UNDER XTRACE (#7797). A probe receives its secrets from the
# sweeper's env, and tracing echoes commands AFTER expansion -- so a credential
# leaks the moment it is used, and the sweeper posts probe output into a public
# issue comment. Unconditional is the safe default for a scaffold, because the
# template cannot know which credentials this probe will end up reading.
#
# If your probe INHERITS a known, fixed set of credentials, you may narrow this
# to a hatch that keeps the script traceable when they are unset:
#
#   case "$-" in
#     *x*)
#       if [ -n "${YOUR_TOKEN:+x}" ]; then   # `:+x` -- `:-` would PRINT the value
#         printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
#         exit 78
#       fi
#       ;;
#   esac
#
# Keep it directly below `set ...`: `scripts/lint-shell-trace-credential-refusal.py`
# requires the refusal in the prologue, before any command that could be traced.
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this probe handles live credentials and -x would print them (see #7797)\n' >&2; exit 78 ;;
esac

# soleur:followthrough-stub v1

echo "PASS: the 2026-10-24 re-evaluation date has been reached. Any box still unticked in the tracking issue (delete_protection on hcloud_volume.git_data_luks, a self-review control on the web-platform-infra-apply environment, the bootstrap listing blind spots) must be re-filed or folded into #10138 BEFORE the first mode=wipe is named."
exit 0
