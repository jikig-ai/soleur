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
#   1 = FAIL      — the evidence exists and records a reboot verdict that is NOT PASS. That is a
#                   real finding: a rehearsal ran the reset arm and the mapper did not reopen.
#   2 = TRANSIENT — no evidence file yet, or the file carries no reboot key at all (the pre-#8210
#                   shape), or the gate could not be read. The rehearsal simply has not run yet,
#                   or has not been landed yet. A FAIL here would post a daily false alarm for
#                   however long the operator takes to schedule the dispatch.
#
# THE READ IS OF `origin/main`, NEVER THE WORKING TREE. A probe that read the checkout would
# report PASS from inside the very PR that adds the evidence, which is the one state where the
# claim is not yet true for anybody else.
set -uo pipefail
# (#7797) No credential is bound here, but xtrace would still echo the gate's internals; keep
# the refusal so the file matches its siblings' shape.
case "$-" in
  *x*) printf '[FATAL] refusing to trace (see #7797)\n' >&2; exit 78 ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EVIDENCE=apps/web-platform/infra/git-data-rung2-boot-evidence.env
TEMPLATE_PATH=apps/web-platform/infra/cloud-init-git-data.yml

cd "$ROOT" || { echo "TRANSIENT: cannot enter the repo root"; exit 2; }

git fetch -q origin main 2>/dev/null || true

body="$(git show "origin/main:${EVIDENCE}" 2>/dev/null)" || body=""
if [[ -z "$body" ]]; then
  echo "TRANSIENT: ${EVIDENCE} does not exist on origin/main — the rung-2 rehearsal has not been"
  echo "dispatched from main (or its evidence has not been landed). The birth and replace routes"
  echo "are HELD until it is, which is the intended safe state, not a defect."
  exit 2
fi

verdict="$(printf '%s\n' "$body" | sed -n 's/^RUNG2_REBOOT_REOPEN=\(.*\)$/\1/p' | head -1)"
if [[ -z "$verdict" ]]; then
  echo "TRANSIENT: origin/main's evidence carries no RUNG2_REBOOT_REOPEN key — it predates the"
  echo "#8210 reset arm. A rehearsal run from main after that merge writes it; nothing to read yet."
  exit 2
fi

if [[ "$verdict" != "PASS" ]]; then
  echo "FAIL: origin/main's evidence records RUNG2_REBOOT_REOPEN=${verdict}."
  echo "A rehearsal ran the reset arm and the mapper did not reopen unattended. Read the run's"
  echo "reboot-probe step: its action= tag names the phase that failed."
  exit 1
fi

# The verdict is only worth anything for the template it was captured against. The gate derives
# that binding itself (a hash of the cloud-init template plus every file() the userdata module
# binds), so asking it is strictly better than re-deriving the hash here — a second
# implementation of the same derivation is a second thing to drift.
# BOTH OPERANDS FROM `origin/main`, and the template is the one that used to leak. An earlier
# revision read the evidence from origin/main and the TEMPLATE from the working tree, so on any
# branch checkout it compared main's evidence against that branch's payload -- while this file's
# own header asserted "THE READ IS OF origin/main, NEVER THE WORKING TREE". Correct under the
# daily sweeper (which runs on main) and wrong everywhere else, which is the shape that survives
# review: the sweeper is the only caller anyone pictures. Materialised to a temp file because the
# gate takes a path.
gate_lib="${ROOT}/tests/scripts/lib/git-data-birth-readiness-gate.sh"
tmpl="$(mktemp -t rung2-tmpl.XXXXXXXX.yml)" || {
  echo "TRANSIENT: could not allocate a temp file for the template read."
  exit 2
}
trap 'rm -f "${tmpl:-}"' EXIT INT TERM HUP
if ! git show "origin/main:${TEMPLATE_PATH}" > "$tmpl" 2>/dev/null || [[ ! -s "$tmpl" ]]; then
  echo "TRANSIENT: could not read ${TEMPLATE_PATH} from origin/main, so the evidence's validity"
  echo "for the CURRENT payload is unverified. Not a verdict about the host."
  exit 2
fi
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

if git_data_rung2_rehearsal_gate "$tmpl" >/dev/null 2>&1; then
  echo "PASS: origin/main carries RUNG2_REBOOT_REOPEN=PASS and the rung-2 gate RELEASES against"
  echo "the current template — the boot-time LUKS reopen (#8210) is proven on a real reset host,"
  echo "and the birth and replace routes are no longer held by this precondition."
  exit 0
fi

echo "TRANSIENT: the evidence records RUNG2_REBOOT_REOPEN=PASS, but the rung-2 gate does NOT"
echo "release against main's current template — the payload has been edited since that rehearsal,"
echo "so the reboot that was proven is not the boot that would happen. A fresh rehearsal is owed."
exit 2
