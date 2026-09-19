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
# FOUR-STATE CONTRACT (the repo's convention — see git-data-boot-poll-8178.sh, this probe's
# nearest sibling, and the rc -> WORD map in scripts/sweep-followthroughs.sh, which is what an
# operator actually reads on the tracker without expanding the fold):
#   0 = PASS      — main's evidence file carries RUNG2_REBOOT_REOPEN=PASS *and* the rung-2 gate
#                   RELEASES against main's current template, so the evidence is valid for the
#                   payload that would actually boot.
#   1 = FAIL      — the evidence exists and records a reboot verdict that is NOT PASS. DEFENSIVE:
#                   no writer produces this today (the capture appends only the literal PASS and
#                   the workflow uploads the artifact only on reboot_rc==0), so a rehearsal whose
#                   reset arm FAILED shows up in the RUN, not here — this probe then reads main's
#                   evidence with no reboot key and stays NOT YET. The branch exists so a
#                   hand-landed non-PASS can never read as "not run yet" (review).
#   2 = NOT YET   — MEASURED, and not yet satisfied: no evidence file, or the file carries no
#                   reboot key at all (the pre-#8210 shape), or this checkout is not main, or the
#                   gate library could not be read or sourced, or the gate LOOKED and refused with
#                   a measured token. The rehearsal simply has not run yet, has not been landed
#                   yet, or landed against a payload that has since moved. A FAIL here would post
#                   a daily false alarm for however long the operator takes to schedule the
#                   dispatch.
#   3 = CANNOT ESTABLISH — the gate could not MEASURE the claim at all (#8010). Since #8010 the
#                   gate resolves the run the evidence names through the GitHub REST API, and
#                   that read can fail for reasons that say nothing about the host: no `jq`, no
#                   network, an anonymous rate limit, an object this checkout cannot resolve, an
#                   unreadable artifact record, an unreadable Sentry verdict. Keyed on the
#                   BRACKETED TOKEN of the gate's verdict line — the could-not-measure set — not
#                   on wording. The split matters because 2 and 3 render differently and mean
#                   different things: `NOT YET` says the answer is no, `CANNOT ESTABLISH` says
#                   there was no answer, and before this split an instrument failure posted
#                   "the rehearsal simply has not run yet" every day for as long as it lasted.
#                   Both leave #8210 open; neither can false-close it.
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
# REFUSES, as NOT YET, when that checkout is not `origin/main` — a branch cannot produce a PASS
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

cd "$ROOT" || { echo "NOT YET: cannot enter the repo root"; exit 2; }

git fetch -q origin main 2>/dev/null || true
head_sha="$(git rev-parse --verify HEAD 2>/dev/null || true)"
main_sha="$(git rev-parse --verify origin/main 2>/dev/null || true)"
if [[ -z "$main_sha" ]]; then
  echo "NOT YET: origin/main is not resolvable in this checkout (no remote, or the fetch failed)."
  echo "The probe reads main by standing on it; nothing was measured."
  exit 2
fi
if [[ "$head_sha" != "$main_sha" ]]; then
  echo "NOT YET: this checkout is ${head_sha:0:12}, not origin/main (${main_sha:0:12}). The probe"
  echo "reads main's evidence WITH main's git history, which only a main checkout carries; on a"
  echo "branch it refuses rather than grade this branch's payload as if it were main's."
  exit 2
fi

if [[ ! -s "$EVIDENCE" ]]; then
  echo "NOT YET: ${EVIDENCE} does not exist on main — the rung-2 rehearsal has not been"
  echo "dispatched from main (or its evidence has not been landed). The birth and replace routes"
  echo "are HELD until it is, which is the intended safe state, not a defect."
  exit 2
fi

verdict="$(sed -n 's/^RUNG2_REBOOT_REOPEN=\(.*\)$/\1/p' "$EVIDENCE" | head -1)"
if [[ -z "$verdict" ]]; then
  echo "NOT YET: main's evidence carries no RUNG2_REBOOT_REOPEN key — it predates the #8210"
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
  echo "NOT YET: the evidence says PASS but the rung-2 gate library could not be read, so its"
  echo "validity for the CURRENT payload is unverified. Not a verdict about the host."
  exit 2
fi
# shellcheck source=tests/scripts/lib/git-data-birth-readiness-gate.sh
source "$gate_lib" 2>/dev/null || {
  echo "NOT YET: could not source the rung-2 gate library."
  exit 2
}
if ! declare -F git_data_rung2_rehearsal_gate >/dev/null; then
  echo "NOT YET: git_data_rung2_rehearsal_gate is not defined after sourcing — the library moved."
  exit 2
fi

gate_out="$(git_data_rung2_rehearsal_gate "$TEMPLATE" 2>&1)"; gate_rc=$?
if [[ "$gate_rc" -eq 0 ]]; then
  echo "PASS: main carries RUNG2_REBOOT_REOPEN=PASS and the rung-2 gate RELEASES against the"
  echo "current template — the boot-time LUKS reopen (#8210) is proven on a real reset host, and"
  echo "the birth and replace routes are no longer held by this precondition."
  exit 0
fi

# THE VERDICT LINE IS SELECTED BY SHAPE, AND PRINTED WHOLE.
#
# Two changes from the `head -1` this replaces, both for the same reader: the sweeper folds this
# output into a comment on #8210, which is the ONLY place it is ever read.
#   * Not positional. Several of the gate's arms print their refusal to stderr, which `2>&1`
#     may interleave ahead of the verdict, so "the first line" is not reliably the line that
#     carries the reason.
#   * Not truncated. Since #8010 each refusal line carries exactly one bracketed token AND the
#     remedy sentence for that token; `head -1` on a multi-line capture handed the operator a
#     cause with no remedy, which is what this probe exists to deliver.
token_line="$(printf '%s\n' "$gate_out" \
  | grep -m1 -E 'git_data_rung2_rehearsal_gate: (HOLD|ABORT) \[[A-Z0-9_]+\]' || true)"
if [[ -n "$token_line" ]]; then
  token="${token_line#*[}"; token="${token%%]*}"
else
  # A refusal with no bracketed token: the gate's pre-#8010 arms still refuse in prose. Fall back
  # to the first line so the cause is never blank. A tokenless refusal is, by construction, not a
  # member of the could-not-measure set, so it takes the NOT YET arm below — fail-closed in the
  # direction that keeps #8210 open either way.
  token_line="$(printf '%s\n' "$gate_out" | head -1)"
  token=""
fi

# The COULD-NOT-MEASURE set, copied from the gate's own contract. Membership is the whole
# decision: every other token means the gate looked at the run and the run was wrong.
case "$token" in
  TOOLING_MISSING|RUN_OFFLINE|RUN_RATE_LIMITED|RUN_UNRESOLVABLE|RUN_SHA_UNREACHABLE|\
  RUN_HASH_UNCOMPUTABLE|RUN_ARTIFACT_RECORD_UNREADABLE|SENTRY_VERDICT_UNREADABLE)
    echo "CANNOT ESTABLISH: main's evidence records RUNG2_REBOOT_REOPEN=PASS, but the rung-2 gate"
    echo "could not MEASURE whether that evidence is valid for the current payload (rc=${gate_rc})."
    echo "This is a statement about the INSTRUMENT, not about the host and not about the payload:"
    echo "nothing here says the rehearsal did not happen or that the evidence is bad. #8210 stays"
    echo "open because the question went unanswered, not because the answer was no."
    echo "The gate's own verdict line, whole — its token names its own remedy:"
    printf '  %s\n' "$token_line"
    echo "Note for whoever reads this comment: the sweeper runs this probe under 'env -i' with no"
    echo "GH_TOKEN, and its workflow grants no 'actions: read', so the gate resolves the run"
    echo "ANONYMOUSLY here — a rate limit or a 403 is expected weather on this path. Re-run the"
    echo "gate locally with GH_TOKEN exported before concluding anything about the evidence:"
    echo "  knowledge-base/engineering/operations/runbooks/git-data-rung2-rehearsal.md"
    exit 3
    ;;
esac

echo "NOT YET: the evidence records RUNG2_REBOOT_REOPEN=PASS, but the rung-2 gate MEASURED that"
echo "claim and refused it (rc=${gate_rc}). The gate looked and the answer was no — one of: the"
echo "payload has been edited since that rehearsal, so the reboot that was proven is not the boot"
echo "that would happen; the run the evidence names is not a completed, successful dispatch of the"
echo "rehearsal workflow on main that uploaded the boot-evidence artifact; the Sentry cross-check"
echo "is fatal, or UNAVAILABLE with no matching acknowledgement; or the evidence's provenance was"
echo "refused. An instrument failure does NOT reach this arm — it exits 3, CANNOT ESTABLISH."
echo "The gate's own verdict line, whole — its token names its own remedy, and the token table is"
echo "in knowledge-base/engineering/operations/runbooks/git-data-rung2-rehearsal.md:"
printf '  %s\n' "$token_line"
exit 2
