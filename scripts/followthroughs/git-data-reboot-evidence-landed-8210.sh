#!/usr/bin/env bash
#
# Follow-through probe for #8210 — has the reboot evidence LANDED on main?
#
# WHY THIS EXISTS. #8210 ships the mechanism (git-data-luks-reopen.service and its reporter)
# and the arm that PROVES it (the rung-2 reset arm). Merging the mechanism proves neither:
# until a rehearsal has been dispatched from `main`, passed its reset arm, and had its evidence
# landed by an evidence-only PR, the claim "the mapper reopens unattended" is an assertion about
# code rather than an observation of a host. The birth and replace routes are both HELD in that
# window by git_data_rung2_rehearsal_gate, which is the intended safe state — not a defect.
#
# So #8210 does not close at merge, and this probe is what closes it without anyone having to
# remember: the daily sweeper runs it and the issue closes when the evidence is really there.
#
# THREE-STATE CONTRACT (the repo's convention — see git-data-birth-emitter-6982.sh):
#   0 = PASS      — main's evidence file carries RUNG2_REBOOT_REOPEN=PASS *and* the rung-2 gate
#                   RELEASES against main's current template, so the evidence is valid for the
#                   payload that would actually boot.
#   1 = FAIL      — the evidence exists and records a reboot verdict that is NOT PASS. DEFENSIVE:
#                   no writer produces this today (the capture appends only the literal PASS and
#                   the workflow uploads the artifact only on reboot_rc==0), so a rehearsal whose
#                   reset arm FAILED shows up in the RUN, not here — this probe then reads main's
#                   evidence with no reboot key and stays TRANSIENT. The branch exists so a
#                   hand-landed non-PASS can never read as "not run yet" (review).
#   2 = TRANSIENT — no evidence file yet, or the file carries no reboot key at all (the pre-#8210
#                   shape), or the gate could not be read, or this checkout is not main. The
#                   rehearsal simply has not run yet, or has not been landed yet. A FAIL here
#                   would post a daily false alarm for however long the operator takes to
#                   schedule the dispatch.
#
# THE READ IS OF `main`, AND THE ONLY WAY TO READ MAIN CORRECTLY HERE IS TO BE ON IT. Three
# revisions of this file each tried to read `origin/main` from an arbitrary checkout and each
# was wrong in a different place, because the gate it calls derives its operands from the
# TEMPLATE'S DIRECTORY: the evidence file beside it, the render module under it, every payload
# that module binds, and — the one no export can satisfy — the evidence's PROVENANCE, read as
# `git log -1 -- <evidence>` + `diff-tree` against the checkout's own history (Guard 4: the
# evidence must never be MODIFIED in a commit that also touches a bound file). Measured:
#   * working-tree template + origin/main evidence  -> compares main's evidence to THIS branch's payload;
#   * a lone `mktemp` copy of main's template        -> "HOLD — no rung-2 boot evidence at /tmp/…",
#                                                       so the probe printed a WRONG cause forever
#                                                       and #8210 could never auto-close;
#   * `git archive origin/main` into a scratch dir   -> hash-valid, then "HOLD — not inside a git
#                                                       work tree, so the evidence has no readable
#                                                       provenance".
# The sweeper (scheduled-followthrough-sweeper.yml) checks out `main` at fetch-depth 0, which is
# exactly the shape the gate wants. So this probe reads the checkout it is standing in and
# REFUSES, as TRANSIENT, when that checkout is not `origin/main` — a branch cannot produce a PASS
# about main from inside the very PR that adds the evidence, and it cannot produce a wrong one.
set -uo pipefail
# (#7797) No credential is bound here, but xtrace would still echo the gate's internals; keep
# the refusal so the file matches its siblings' shape.
case "$-" in
  *x*) printf '[FATAL] refusing to trace (see #7797)\n' >&2; exit 78 ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEMPLATE=apps/web-platform/infra/cloud-init-git-data.yml
EVIDENCE=apps/web-platform/infra/git-data-rung2-boot-evidence.env

cd "$ROOT" || { echo "TRANSIENT: cannot enter the repo root"; exit 2; }

git fetch -q origin main 2>/dev/null || true
head_sha="$(git rev-parse --verify HEAD 2>/dev/null || true)"
main_sha="$(git rev-parse --verify origin/main 2>/dev/null || true)"
if [[ -z "$main_sha" ]]; then
  echo "TRANSIENT: origin/main is not resolvable in this checkout (no remote, or the fetch failed)."
  echo "The probe reads main by standing on it; nothing was measured."
  exit 2
fi
if [[ "$head_sha" != "$main_sha" ]]; then
  echo "TRANSIENT: this checkout is ${head_sha:0:12}, not origin/main (${main_sha:0:12}). The probe"
  echo "reads main's evidence WITH main's git history, which only a main checkout carries; on a"
  echo "branch it refuses rather than grade this branch's payload as if it were main's."
  exit 2
fi

if [[ ! -s "$EVIDENCE" ]]; then
  echo "TRANSIENT: ${EVIDENCE} does not exist on main — the rung-2 rehearsal has not been"
  echo "dispatched from main (or its evidence has not been landed). The birth and replace routes"
  echo "are HELD until it is, which is the intended safe state, not a defect."
  exit 2
fi

verdict="$(sed -n 's/^RUNG2_REBOOT_REOPEN=\(.*\)$/\1/p' "$EVIDENCE" | head -1)"
if [[ -z "$verdict" ]]; then
  echo "TRANSIENT: main's evidence carries no RUNG2_REBOOT_REOPEN key — it predates the #8210"
  echo "reset arm. A rehearsal run from main after that merge writes it; nothing to read yet."
  exit 2
fi

if [[ "$verdict" != "PASS" ]]; then
  echo "FAIL: main's evidence records RUNG2_REBOOT_REOPEN=${verdict}."
  echo "A rehearsal ran the reset arm and the mapper did not reopen unattended. Read the run's"
  echo "reboot-probe step: its action= tag names the phase that failed."
  exit 1
fi

# The verdict is only worth anything for the template it was captured against. The gate derives
# that binding itself (a hash of the cloud-init template plus every file() the userdata module
# binds, plus Guard 4's provenance read), so asking it is strictly better than re-deriving any of
# it here — a second implementation of the same derivation is a second thing to drift.
gate_lib="${ROOT}/tests/scripts/lib/git-data-birth-readiness-gate.sh"
if [[ ! -r "$gate_lib" ]]; then
  echo "TRANSIENT: the evidence says PASS but the rung-2 gate library could not be read, so its"
  echo "validity for the CURRENT payload is unverified. Not a verdict about the host."
  exit 2
fi
# shellcheck source=tests/scripts/lib/git-data-birth-readiness-gate.sh
source "$gate_lib" 2>/dev/null || {
  echo "TRANSIENT: could not source the rung-2 gate library."
  exit 2
}
if ! declare -F git_data_rung2_rehearsal_gate >/dev/null; then
  echo "TRANSIENT: git_data_rung2_rehearsal_gate is not defined after sourcing — the library moved."
  exit 2
fi

gate_out="$(git_data_rung2_rehearsal_gate "$TEMPLATE" 2>&1)"; gate_rc=$?
if [[ "$gate_rc" -eq 0 ]]; then
  echo "PASS: main carries RUNG2_REBOOT_REOPEN=PASS and the rung-2 gate RELEASES against the"
  echo "current template — the boot-time LUKS reopen (#8210) is proven on a real reset host, and"
  echo "the birth and replace routes are no longer held by this precondition."
  exit 0
fi

echo "TRANSIENT: the evidence records RUNG2_REBOOT_REOPEN=PASS, but the rung-2 gate does NOT"
echo "release against main's current template (rc=${gate_rc}). Either the payload has been edited"
echo "since that rehearsal, so the reboot that was proven is not the boot that would happen, or"
echo "the evidence's provenance was refused. The gate's own first line:"
printf '  %s\n' "$(printf '%s\n' "$gate_out" | head -1)"
exit 2
