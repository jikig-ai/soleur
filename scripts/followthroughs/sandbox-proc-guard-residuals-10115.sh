#!/usr/bin/env bash
# sandbox-proc-guard-residuals-10115.sh — re-evaluation trigger for the residual gaps of the sandbox
# masked-/proc guards tracked in #10115.
#
# EVENT-GREP, not a dependency probe: residual 1 of #10115 is that `overlay_github_app_key`'s runtime-hijack
# class list in apps/web-platform/infra/ci-deploy.sh does not refuse the SOLEUR_BWRAP_* names the bwrap shim
# honours. This probe reads that file on `main` and passes when the hijack-class line (the `_gak_hij=$(grep -E`
# line) names SOLEUR_. A dependency on another PR's merge says nothing about whether the edit landed.
#
# PASS (0) closes the tracker, so the PASS text names the residuals that are STILL OPEN (2-4 of #10115) and says to
# re-file them: closing the tracker must not drop them.
#
# CREDENTIAL POSTURE: declares `secrets=GH_TOKEN`; the only reads are authenticated GitHub contents-API reads of
# `main` (no write, no other credential). Never run under xtrace (handled below).
#
# Exit semantics (enforced by scripts/sweep-followthroughs.sh):
#   0 = PASS (the hijack-class line on main names SOLEUR_)
#   2 = TRANSIENT (still not there, or gh/the API could not answer, or the anchor line moved: update this probe)
#   78 = refused to run under xtrace (lands in the TRANSIENT bucket, #7797)
# Never exits 1 (no FAIL verdict exists for "not yet").
#
# RETIREMENT: when #10115 closes, delete this file. Live references to it: the directive in #10115's body only
# (`git grep sandbox-proc-guard-residuals` finds this file and nothing else in live code).
# Convention: knowledge-base/engineering/operations/runbooks/followthrough-convention.md

set -uo pipefail

# REFUSE TO RUN UNDER XTRACE (#7797): the sweeper hands this probe GH_TOKEN; tracing would echo it after expansion.
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this probe handles live credentials and -x would print them (see #7797)\n' >&2; exit 78 ;;
esac

# soleur:followthrough-stub v1

command -v gh >/dev/null 2>&1 || { echo "TRANSIENT: gh is not installed" >&2; exit 2; }

body="" rc=0
body="$(gh api -H 'Accept: application/vnd.github.raw' 'repos/jikig-ai/soleur/contents/apps/web-platform/infra/ci-deploy.sh?ref=main' 2>/dev/null)" || rc=$?
if [[ "$rc" -ne 0 || -z "$body" ]]; then
  echo "TRANSIENT: could not read apps/web-platform/infra/ci-deploy.sh on main (gh rc=$rc)" >&2
  exit 2
fi

# The hijack-class line. A moved anchor is a probe fault, not a verdict about the residual: report it as TRANSIENT.
# shellcheck disable=SC2016  # the anchor is a literal source fragment, not an expansion
anchor="$(grep -E '^[[:space:]]*_gak_hij=\$\(grep -E' <<<"$body" | head -1)"
if [[ -z "$anchor" ]]; then
  echo "TRANSIENT: the '_gak_hij=\$(grep -E' hijack-class line was not found in ci-deploy.sh on main; the function moved, update this probe" >&2
  exit 2
fi

if grep -qF 'SOLEUR_' <<<"$anchor"; then
  echo "PASS: the runtime-hijack class list in ci-deploy.sh on main now names SOLEUR_* (residual 1 of #10115 is closed)."
  echo "Residuals 2-4 of #10115 are STILL OPEN (outer-wrap replay under docker's masks; the suite container is base image + apt bubblewrap, not the runner stage; the census scope of docker-run-tuple.py): re-file each as its own issue before relying on this closure."
  exit 0
fi
echo "TRANSIENT: the runtime-hijack class list in ci-deploy.sh on main does not name SOLEUR_* yet (residual 1 of #10115 is open)" >&2
exit 2
