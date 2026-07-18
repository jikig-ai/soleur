#!/usr/bin/env bash
# Pins the [ack-destroy] regex across all seven sites where it lives — the
# three apply-* workflows, the three destroy-guard test scripts that mirror
# their control flow, AND the PR-time squash-ack detector (#6589).
#
# The regex `(^|$'\n')\[ack-destroy\]($|$'\n')` is load-bearing across all
# seven files: any drift silently breaks the operator-acknowledgement gate.
# CODEOWNERS @deruelle gates approval but not content coherence — this
# script is the deterministic coherence check.
#
# THE 7th SITE IS THE HIGHEST-STAKES ONE (#6589). scripts/sentry-squash-ack-detect.sh
# answers the PR-time question "will a pre-staged [ack-destroy] satisfy the
# apply gate after squash?". Its verdict and the apply gate's verdict MUST agree.
# If this file's regex drifts from apply-sentry-infra.yml's, the PR gate greens
# and the post-merge apply reds — the resource stays live and billing, which is
# the exact #6074 end state this whole PR exists to make impossible. Divergence
# between a predictor and the thing it predicts is invisible to review; it is
# checked here mechanically instead.
#
# Closes #4419 review-finding F2 (pattern-recognition-specialist).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$REPO_ROOT/.." && pwd)"

# Byte-identical regex (with the bash $'\n' ANSI-C-quoting). All seven sites
# MUST contain a line matching this exact literal after the `=~` operator:
#   (^|$'\n')\[ack-destroy\]($|$'\n')
# The grep below uses `-F` (literal) to avoid regex-meta-on-regex confusion.
EXPECTED_SITES=(
  ".github/workflows/apply-github-infra.yml"
  ".github/workflows/apply-sentry-infra.yml"
  ".github/workflows/apply-web-platform-infra.yml"
  "tests/scripts/test-destroy-guard-counter.sh"
  "tests/scripts/test-destroy-guard-counter-sentry.sh"
  "tests/scripts/test-destroy-guard-counter-web-platform.sh"
  # #6589 — the PR-time predictor of the apply gate's verdict. Must agree with
  # apply-sentry-infra.yml or the PR greens while the apply reds (see header).
  "scripts/sentry-squash-ack-detect.sh"
)

fail=0
for site in "${EXPECTED_SITES[@]}"; do
  path="$REPO_ROOT/$site"
  if [[ ! -f "$path" ]]; then
    echo "[FAIL] $site does not exist" >&2
    fail=$((fail + 1))
    continue
  fi
  if grep -qF "(^|\$'\\n')\\[ack-destroy\\](\$|\$'\\n')" "$path"; then
    echo "[ok] $site"
  else
    echo "[FAIL] $site: canonical [ack-destroy] regex not found" >&2
    fail=$((fail + 1))
  fi
done

if [[ "$fail" -gt 0 ]]; then
  echo "=== $fail site(s) drifted from canonical regex ===" >&2
  printf 'Canonical literal:  (^|$%s\\n%s)\\[ack-destroy\\]($|$%s\\n%s)\n' \
    "'" "'" "'" "'" >&2
  exit 1
fi

echo "=== ${#EXPECTED_SITES[@]} sites all carry the canonical [ack-destroy] regex ==="

# ---------------------------------------------------------------------------
# 7th surface (#6416): the `host_creates` HALT's CONTROL FLOW.
#
# WHY THIS LIVES HERE. The counter tests
# (test-destroy-guard-counter-web-platform.sh) exercise a hand-written mirror of
# the workflow's bash, so they pin the jq filter's COUNTING but cannot pin the
# workflow's HALT. Demonstrated at review: deleting the entire `host_creates`
# HALT block from apply-web-platform-infra.yml left that whole suite GREEN — the
# gate the PR exists to add could be removed and nothing noticed. This file is
# the repo's designated coherence check for exactly that gap (see header:
# "CODEOWNERS gates approval but not content coherence").
#
# The three properties below are the HALT's entire contract. Each is asserted
# against the workflow's literal bytes, so removing or weakening any one of them
# fails here even though every counter test still passes.
# ---------------------------------------------------------------------------
WF="$REPO_ROOT/.github/workflows/apply-web-platform-infra.yml"
hc_fail=0

# The three literals below are the workflow's SOURCE TEXT, matched with `grep -F`. The single
# quotes are load-bearing: the text contains `$host_creates` verbatim, and letting the shell
# expand it would search for the empty string and pass vacuously — the exact false-green this
# block exists to prevent.
# shellcheck disable=SC2016
HALT_PATTERN='if [[ "$host_creates" -gt 0 ]]; then'
# shellcheck disable=SC2016
SUM_PATTERN='destroy_count=$((resource_deletes + nested_deletes + reboot_updates))'
# shellcheck disable=SC2016
NUMERIC_PATTERN='! "$host_creates" =~ ^[0-9]+$'

# (1) The HALT exists at all.
if grep -qF "$HALT_PATTERN" "$WF"; then
  echo "[ok] host_creates HALT present"
else
  echo "[FAIL] host_creates HALT missing from apply-web-platform-infra.yml — a per-PR apply can birth an unattached host (#6416)" >&2
  hc_fail=$((hc_fail + 1))
fi

# (2) The HALT precedes the destroy_count sum. This is what makes it ack-INDEPENDENT:
# `[ack-destroy]` is parsed and consulted only by the destroy gate below the sum, so a HALT
# above it cannot be typed past. Order is the guarantee — assert the order, not just presence.
halt_line=$(grep -nF "$HALT_PATTERN" "$WF" | head -1 | cut -d: -f1)
sum_line=$(grep -nF "$SUM_PATTERN" "$WF" | head -1 | cut -d: -f1)
if [[ -n "$halt_line" && -n "$sum_line" && "$halt_line" -lt "$sum_line" ]]; then
  echo "[ok] host_creates HALT (line $halt_line) precedes the destroy_count sum (line $sum_line) — no [ack-destroy] bypass"
else
  echo "[FAIL] host_creates HALT must precede the destroy_count sum (halt=${halt_line:-absent} sum=${sum_line:-absent}); below it, [ack-destroy] would bypass a host create/replace" >&2
  hc_fail=$((hc_fail + 1))
fi

# (3) host_creates is in the fail-closed numeric validation. Without it an empty value from a
# jq failure evaluates false in the `-gt 0` test and the guard ships fail-OPEN — the exact
# hazard that block's own comment documents.
if grep -qF "$NUMERIC_PATTERN" "$WF"; then
  echo "[ok] host_creates is in the numeric-parse validation (fail-closed)"
else
  echo "[FAIL] host_creates missing from the numeric-parse validation — a jq failure would silently evaluate false and let a host create through" >&2
  hc_fail=$((hc_fail + 1))
fi

if [[ "$hc_fail" -gt 0 ]]; then
  echo "=== $hc_fail host_creates HALT contract violation(s) ===" >&2
  exit 1
fi

echo "=== host_creates HALT contract intact (present, pre-sum, fail-closed) ==="

# ---------------------------------------------------------------------------
# AC-B5 (#6538) — the destroy_count HALT must steer to [skip-web-platform-apply],
# not to a bare [ack-destroy].
#
# WHY. During the web-2 retirement window, config says 1 web host while state
# still says 2. ANY unrelated merge to main in that window runs the per-PR apply,
# whose plan shows the web-2 server destroy and trips this HALT. The pre-#6538
# text read: "Add a line containing exactly '[ack-destroy]' ... or revert the
# trigger commit." Both of its options are wrong here:
#   - [ack-destroy] authorizes the PARTIAL destroy. The per-PR apply scope reaches
#     hcloud_server.web["web-2"] but NOT hcloud_volume.workspaces["web-2"]
#     (measured 2026-07-17: `0 to add, 1 to change, 1 to destroy`). The host dies,
#     the 20 GB volume strands and bills with nothing attached.
#   - "revert the trigger commit" points at an INNOCENT merge. The trigger is not
#     the cause; PR B is.
# The correct move is to suppress that merge's apply with
# [skip-web-platform-apply] and let the supervised operator-local 5-target apply
# (B6.2/B6.4) complete the retirement.
#
# This asserts TEXT, which is ordinarily weak. It is load-bearing here because the
# text IS the interface: it is the only instruction the operator sees at 3am on an
# unrelated PR, and following the old one strands a billing volume.
b5_fail=0

# The steer must name the token that actually resolves this safely.
#
# ANCHORED, not a bare token grep (cq-assert-anchor-not-bare-token). A whole-file
# `grep -qF 'skip-web-platform-apply'` FALSE-PASSES: the literal already appears
# four times in this workflow (the kill-switch header, the skip-check regex, and
# the host_creates UNWEDGE steer at ~line 455) with no change to the destroy HALT
# at all. Verified: this assertion passed against the unmodified file. Anchor to
# the DESTROY steer specifically — an ::error:: line that names the token AND the
# retirement-window condition, which no pre-existing line does.
# Order-independent: assert the CONTRACT (one ::error:: line naming BOTH the
# retirement condition and the skip token), not a fixed word order. Pinning prose
# would make a harmless rewording red-CI. Requiring both tokens ON THE SAME LINE
# is what excludes the pre-existing occurrences: the kill-switch header and skip
# regex are not ::error:: lines, and the host_creates UNWEDGE steer (~line 455)
# names the token but says nothing about a retirement.
if grep -qE "::error::.*(retirement.*skip-web-platform-apply|skip-web-platform-apply.*retirement)" "$WF"; then
  echo "[ok] AC-B5 destroy HALT names [skip-web-platform-apply] (anchored to the destroy steer)"
else
  echo "[FAIL] AC-B5: the destroy_count HALT does not steer to [skip-web-platform-apply] — an unrelated merge during a retirement window would be steered to ack-through a PARTIAL destroy (server dies, volume strands)" >&2
  b5_fail=$((b5_fail + 1))
fi

# The ack must carry its partial-destroy warning, not be offered bare.
if grep -qE '::error::.*ack-destroy.*(partial|PARTIAL)' "$WF"; then
  echo "[ok] AC-B5 [ack-destroy] carries an explicit partial-destroy warning"
else
  echo "[FAIL] AC-B5: [ack-destroy] is offered without warning that it may authorize a PARTIAL destroy" >&2
  b5_fail=$((b5_fail + 1))
fi

# The old bare steer must be gone — otherwise both texts ship and the operator
# reads whichever comes first.
if grep -qF "Add a line containing exactly '[ack-destroy]' to the merge commit message to acknowledge, or revert the trigger commit." "$WF"; then
  echo "[FAIL] AC-B5: the pre-#6538 bare steer ('...or revert the trigger commit.') is still present in apply-web-platform-infra.yml" >&2
  b5_fail=$((b5_fail + 1))
else
  echo "[ok] AC-B5 pre-#6538 bare steer removed from the web-platform apply"
fi

# SCOPE PIN. apply-github-infra.yml and apply-sentry-infra.yml carry the same
# literal but NOT this hazard — neither has a volume that can strand behind a
# scoped server destroy. They keep the original text deliberately. If a future
# change propagates the web-platform wording to them, that is a signal the hazard
# analysis was copied rather than re-derived; assert they are untouched.
for sibling in .github/workflows/apply-github-infra.yml .github/workflows/apply-sentry-infra.yml; do
  if grep -qF 'skip-web-platform-apply' "$REPO_ROOT/$sibling"; then
    echo "[FAIL] AC-B5 scope: $sibling mentions [skip-web-platform-apply] — that token is web-platform-only; these workflows carry no stranding hazard and must keep the original steer" >&2
    b5_fail=$((b5_fail + 1))
  fi
done
if [[ "$b5_fail" -eq 0 ]]; then
  echo "[ok] AC-B5 scope: sibling apply workflows unchanged (no stranding hazard there)"
fi

if [[ "$b5_fail" -gt 0 ]]; then
  echo "=== $b5_fail AC-B5 destroy-HALT steer violation(s) ===" >&2
  exit 1
fi

echo "=== AC-B5 destroy-HALT steer intact (skip-token named, ack warned, scope pinned) ==="
