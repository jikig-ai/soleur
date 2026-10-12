#!/usr/bin/env bash
# sandbox-proc-guard-residuals-10115.sh — re-evaluation trigger for the residual gaps of the sandbox
# masked-/proc guards tracked in #10115 (dependency form: "re-evaluate when #10063 lands").
#
# #10063 is the open PR that edits apps/web-platform/infra/ci-deploy.sh and cloud-init.yml (the kernel-stream
# read for the deploy user). The residual that most needs a production deploy-path edit (the SOLEUR_BWRAP_*
# names missing from overlay_github_app_key's runtime-hijack classes) can ride the next deploy-path change, so
# when #10063 is MERGED or CLOSED the sweeper closes the tracker with a comment and the residuals must be
# re-decided then (fixed inline in a ci-deploy.sh PR, or re-filed), not dropped.
#
# Exit semantics (enforced by scripts/sweep-followthroughs.sh):
#   0 = PASS (#10063 is MERGED or CLOSED), 2 = TRANSIENT (still open, or gh could not answer).
# Convention: knowledge-base/engineering/operations/runbooks/followthrough-convention.md

set -uo pipefail

# REFUSE TO RUN UNDER XTRACE (#7797): the sweeper hands this probe GH_TOKEN; tracing would echo it after expansion.
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this probe handles live credentials and -x would print them (see #7797)\n' >&2; exit 78 ;;
esac

# soleur:followthrough-stub v1

state="" rc=0
state="$(gh issue view 10063 --json state --jq .state 2>/dev/null)" || rc=$?
if [[ "$rc" -ne 0 || -z "$state" ]]; then
  echo "TRANSIENT: could not read the state of #10063 (gh rc=$rc)" >&2
  exit 2
fi
case "$state" in
  MERGED|CLOSED) echo "PASS: #10063 is $state; re-evaluate the residual gaps in #10115"; exit 0 ;;
  *) echo "TRANSIENT: #10063 is still $state" >&2; exit 2 ;;
esac
