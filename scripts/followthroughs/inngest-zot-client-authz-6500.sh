#!/usr/bin/env bash
# #6500 — operator authorization that soleur-inngest is enrolled as a zot client.
#
# TRACKER: **#6500**, which is OPEN and must stay open until an operator says otherwise.
#
# WHY THIS IS NOT A TELEMETRY PROBE. #6500's technical precondition — the dedicated inngest host
# resolving its bootstrap image from zot — is verified by inngest-host-not-serving-7674.sh on #7674. (RE-POINTED 2026-08-25: the former
# probe was retired and #7462 closed, so that reference named a check that no longer runs.) This
# probe deliberately does NOT re-measure that. Closing #6500 is an AUTHORIZATION act: it gates
# ADR-096 Phase 5.3-5.5 (retiring GHCR push/egress), and zot-soak-6122.sh's blocker arm reads
# #6500's state to decide whether that retirement may proceed. Auto-closing it from telemetry would
# let a green boot marker authorize a supply-chain retirement no human agreed to.
#
# So the close-criterion is a human verdict, mechanized the way the stub template sanctions
# (plugins/soleur/skills/ship/references/followthrough-stub-template.sh, "Operator-confirmed").
#
# TO CLOSE: comment on #6500 with a line that is EXACTLY, at line start:
#   RESULT: PASS
# To retract a verdict already given, comment:
#   RESULT: FAIL
#
# FAIL IS EVALUATED BEFORE PASS, AND THE ORDER IS THE WHOLE POINT. Checking PASS first lets a
# retraction lose to the string it is retracting: an operator who posts `RESULT: FAIL` after an
# earlier `RESULT: PASS` would still close the issue, because the PASS comment is still there. The
# sibling operator-confirmed probe's harness failed on exactly this ordering (#7437,
# cpx22-invoice-reconcile-7431.sh). Latest-verdict-wins is NOT implemented here on purpose:
# "any FAIL anywhere blocks" is the safe polarity for an authorization gate, and it degrades toward
# staying open rather than toward closing.
#
# THE ANCHOR IS LINE-START AND EXACT. An unanchored grep closes the issue on a comment ASKING about
# the result ("what's the RESULT: PASS criterion here?"), which is the same class the #7437 harness
# pins. `grep -E '^RESULT: (PASS|FAIL)$'` over `.body` split into lines, never a substring test.
#
# EXIT CONTRACT (scripts/sweep-followthroughs.sh):
#   0 = PASS       an operator posted `RESULT: PASS` and no `RESULT: FAIL` follows anywhere.
#   2 = TRANSIENT  no verdict yet (the expected steady state), or the API did not answer.
#   1 = FAIL       an operator posted `RESULT: FAIL` — a recorded refusal to authorize, which
#                  should surface rather than sit silent. This is the only exit-1 path.
#
# THE `${VAR:?msg}` FORM IS BANNED HERE — under the sweeper's non-interactive shell it aborts with
# status 1, which this contract reads as FAIL, so an unprovisioned secret would post a daily
# false-FAIL forever. scripts/lint-followthrough-varq-ban.sh reddens CI on it.
#
# Required env (the sweeper runs probes under `env -i` with PATH + HOME + the directive-declared
# `secrets=` ONLY):
#   GH_TOKEN
set -uo pipefail

ISSUE="${INNGEST_AUTHZ_6500_ISSUE:-6500}"
REPO="${INNGEST_AUTHZ_6500_REPO:-jikig-ai/soleur}"
GH_BIN="${INNGEST_AUTHZ_6500_GH_BIN:-gh}"

if [[ -z "${GH_TOKEN:-}" ]]; then
  echo "TRANSIENT: reason=credentials_unprovisioned — GH_TOKEN is unset." >&2
  echo "           No verdict was read, so this says nothing about whether one exists." >&2
  exit 2
fi

bodies="$("$GH_BIN" issue view "$ISSUE" --repo "$REPO" --comments --json comments \
          --jq '.comments[].body' 2>/dev/null)"
grc=$?
if [[ "$grc" -ne 0 ]]; then
  echo "TRANSIENT: reason=api_unavailable rc=${grc} — could not read #${ISSUE}'s comments." >&2
  exit 2
fi

# Split to lines, then anchor. A comment body is multi-line; `grep` over the joined blob with `^`
# would still work, but going through the same normalization for both verdicts keeps the two arms
# symmetric — an asymmetry here is how one verdict ends up easier to post than the other.
n_fail="$(printf '%s\n' "$bodies" | tr -d '\r' | grep -cxE 'RESULT: FAIL' || true)"
n_pass="$(printf '%s\n' "$bodies" | tr -d '\r' | grep -cxE 'RESULT: PASS' || true)"
[[ "$n_fail" =~ ^[0-9]+$ ]] || n_fail=0
[[ "$n_pass" =~ ^[0-9]+$ ]] || n_pass=0

# FAIL FIRST. See the header — this ordering is the difference between a retraction working and a
# retraction being ignored.
if [[ "$n_fail" -gt 0 ]]; then
  echo "FAIL: reason=authorization_refused — ${n_fail} 'RESULT: FAIL' verdict(s) on #${ISSUE}." >&2
  echo "      An operator has recorded a refusal to authorize ADR-096 Phase 5.3-5.5." >&2
  echo "      This blocks even if a 'RESULT: PASS' also exists (${n_pass} found): any refusal wins," >&2
  echo "      because the safe polarity for an authorization gate is to stay open." >&2
  exit 1
fi

if [[ "$n_pass" -eq 0 ]]; then
  echo "TRANSIENT: reason=awaiting_operator_verdict — no 'RESULT: PASS' line on #${ISSUE} yet." >&2
  echo "           This is the EXPECTED steady state. #6500 closes when an operator authorizes" >&2
  echo "           it, not when telemetry looks good; the technical precondition is measured" >&2
  echo "           separately by inngest-host-not-serving-7674.sh on #7674." >&2
  exit 2
fi

echo "PASS: an operator authorized #${ISSUE} (${n_pass} 'RESULT: PASS' verdict(s), zero refusals)."
echo "      soleur-inngest is accepted as an enrolled zot client, so ADR-096 Phase 5.3-5.5"
echo "      (retiring GHCR push/egress) is unblocked."
echo "      This probe reads a HUMAN verdict by design and re-measures no telemetry."
exit 0
