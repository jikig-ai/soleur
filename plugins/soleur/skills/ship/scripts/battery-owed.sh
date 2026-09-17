#!/usr/bin/env bash
# Decide whether `/ship` Phase 4 still owes a full local `test-all.sh` run.
#
# EXIT CONTRACT (the caller branches on this, never on the prose):
#   0  OWED         — run the battery
#   1  SKIPPABLE    — CI already verified this exact tree; running it again buys nothing
#   2  UNDECIDABLE  — could not determine; the caller MUST treat this as OWED
#
# Exit 2 exists so "the check could not run" is never silently folded into
# "the check says skip". Every failure path below reaches 0 or 2, never 1.
#
# WHY THIS EXISTS (#8247). CI's required `test` context aggregates
# test-webplat + test-bun + test-scripts + web-platform-build — the same three
# `test-all.sh` shards this battery runs — on the pushed head. The skill also
# mandates re-running the battery after any post-Phase-4 change (a review fix, a
# main sync, an advisor fix), and on that re-run path the work is frequently a
# pure duplicate. Measured on PR #8233: two full batteries, ~70 min, the second
# finishing against a head whose 26/26 required checks were already green on the
# identical SHA. It could not have changed the merge decision.
#
# WHAT THIS IS NOT. It does not make CI the local fail-fast checkpoint and it
# weakens no merge gate. At FIRST run Phase 4 precedes the Phase 6 push, so
# there is usually no CI for HEAD and this returns OWED — by design. The saving
# is concentrated on the re-run path, which is where the duplicate cost lives.
set -uo pipefail

VERDICT_OWED=0
VERDICT_SKIPPABLE=1
VERDICT_UNDECIDABLE=2

say() { printf 'battery-owed: %s\n' "$*"; }

owed()        { say "OWED — $1";        exit "$VERDICT_OWED"; }
skippable()   { say "SKIPPABLE — $1";   exit "$VERDICT_SKIPPABLE"; }
undecidable() { say "UNDECIDABLE — $1 (caller must treat as OWED)"; exit "$VERDICT_UNDECIDABLE"; }

command -v git >/dev/null 2>&1 || undecidable "git not on PATH"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || undecidable "not inside a work tree"

# ---------------------------------------------------------------------------
# Grok arm — redundant with the push-time gate, and redundant WITHOUT needing CI.
#
# On Grok, `grok-pre-push-gate.sh` invokes `scripts/test-all.sh` with no
# TEST_GROUP at push time, on the tree actually being pushed, and aborts the push
# on a non-zero rc. So that arm runs the full battery TWICE per PR, and ship's own
# prose already calls the Phase 4 run "redundant on the Grok arm" — it just never
# acted on it.
#
# This skip is strictly safer than the CI-based one below: the push-time run
# covers the same shards on a LATER tree (the one being pushed), so nothing is
# lost even if the tree changes after Phase 4. It therefore does not depend on any
# of the four conditions that follow, and is evaluated before them.
#
# Detected by the same two variables `plugins/soleur/lib/harness.ts` uses. The
# gate script must actually exist: on a self-hosted install where it is absent,
# there is no second run to be redundant with, and this must not fire.
if [[ -n "${GROK_HOME:-}" || -n "${GROK_AGENT:-}" ]]; then
  GROK_GATE="$(git rev-parse --show-toplevel 2>/dev/null)/plugins/soleur/scripts/grok-pre-push-gate.sh"
  if [[ -r "$GROK_GATE" ]]; then
    say "NOTE: Grok arm — grok-pre-push-gate.sh re-runs test-all.sh at push time on"
    say "NOTE: the pushed tree and aborts the push on failure, so this run is a duplicate."
    skippable "Grok harness detected and grok-pre-push-gate.sh is present; the push-time battery supersedes this one"
  fi
fi

# ---------------------------------------------------------------------------
# Condition 1 — the local tree must BE what CI verified.
#
# This is the sharpest of the four. A green run on an ancestor SHA is not
# evidence about your working tree, and nothing downstream can recover from
# getting it wrong: every later condition would be measuring a different tree
# than the one about to be shipped.
# ---------------------------------------------------------------------------
DIRTY="$(git status --porcelain 2>/dev/null)"
rc=$?
(( rc == 0 )) || undecidable "git status failed (rc=$rc)"
[[ -n "$DIRTY" ]] && owed "working tree is dirty; CI verified a different tree"

BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
[[ -n "$BRANCH" && "$BRANCH" != "HEAD" ]] || undecidable "detached HEAD or unresolvable branch"

HEAD_SHA="$(git rev-parse HEAD 2>/dev/null)"
[[ "$HEAD_SHA" =~ ^[0-9a-f]{40}$ ]] || undecidable "could not resolve a full HEAD sha"

# The upstream ref must exist AND be current. A stale tracking ref reports zero
# unpushed commits for a branch that is in fact ahead — the same stale-ref class
# the unpushed-commits gate fails closed on.
if ! git rev-parse --verify --quiet "refs/remotes/origin/${BRANCH}" >/dev/null 2>&1; then
  owed "no origin/${BRANCH} tracking ref; nothing has been pushed for CI to verify"
fi
if ! git fetch origin "$BRANCH" --quiet 2>/dev/null; then
  undecidable "could not fetch origin/${BRANCH}; the unpushed count would be read off a stale ref"
fi
UNPUSHED="$(git rev-list "origin/${BRANCH}..HEAD" --count 2>/dev/null)"
rc=$?
(( rc == 0 )) || undecidable "could not count unpushed commits (rc=$rc)"
(( UNPUSHED > 0 )) && owed "${UNPUSHED} unpushed commit(s); CI has not seen this tree"

# ---------------------------------------------------------------------------
# Condition 2 — the infra shard, where this battery is the ONLY gate.
#
# No required status check runs `apps/web-platform/infra/`'s registered suites
# (verified: no row in scripts/required-checks.txt; tracked as #6480). So for a
# diff touching that tree the local run holds UNIQUE BLOCKING AUTHORITY, and
# skipping it would not be redundant — it would delete the only gate those
# suites have. Retire this condition if #6480 lands.
# ---------------------------------------------------------------------------
if ! git rev-parse --verify --quiet refs/remotes/origin/main >/dev/null 2>&1; then
  undecidable "origin/main is unresolvable; cannot scope the diff"
fi
CHANGED="$(git diff --name-only origin/main...HEAD 2>/dev/null)"
rc=$?
(( rc == 0 )) || undecidable "could not compute the branch diff (rc=$rc)"
if printf '%s\n' "$CHANGED" | grep -qE '^apps/[^/]+/infra/'; then
  owed "diff touches apps/*/infra/**, which no required check covers (#6480) — the battery is the only gate there"
fi

# ---------------------------------------------------------------------------
# Condition 3 — every required context PRESENT and green on this exact SHA.
#
# PRESENCE IS ASSERTED, never inferred from "nothing is failing". An empty
# rollup on a just-pushed head satisfies "no failures" vacuously, so a
# failure-only scan would report a clean sweep having examined nothing. This is
# the same non-vacuity trap `/ship` Phase 6.5 documents for `gh pr checks`.
#
# The LIVE ruleset is authoritative, not scripts/required-checks.txt: the file
# is a mirror and can drift, and a drifted mirror under-requires, which fails
# in the unsafe direction. If the ruleset cannot be read we return UNDECIDABLE
# rather than falling back to the file.
# ---------------------------------------------------------------------------
command -v gh >/dev/null 2>&1 || undecidable "gh not on PATH; cannot read CI state"
command -v jq >/dev/null 2>&1 || undecidable "jq not on PATH; cannot read CI state"

REQUIRED_JSON="$(gh api 'repos/{owner}/{repo}/rules/branches/main' \
  --jq '[.[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context]' 2>/dev/null)"
rc=$?
(( rc == 0 )) || undecidable "could not read the branch ruleset (rc=$rc)"
[[ -n "$REQUIRED_JSON" ]] || undecidable "ruleset returned no payload"

REQUIRED_COUNT="$(jq 'length' <<<"$REQUIRED_JSON" 2>/dev/null)"
[[ "$REQUIRED_COUNT" =~ ^[0-9]+$ ]] || undecidable "could not parse the required-context list"
(( REQUIRED_COUNT > 0 )) || undecidable "the ruleset declares zero required contexts; refusing to skip on an empty requirement set"

# --paginate is load-bearing: the check-runs API defaults to 30 per page, and a
# truncated page is indistinguishable from a short one. A missed required check
# would read as ABSENT below and correctly force OWED, but a missed *green* one
# would too — so without this the gate is merely noisy rather than unsafe.
CHECKS="$(gh api --paginate "repos/{owner}/{repo}/commits/${HEAD_SHA}/check-runs" \
  --jq '.check_runs[] | {name: .name, status: .status, conclusion: .conclusion}' 2>/dev/null | jq -s '.')"
rc=$?
(( rc == 0 )) || undecidable "could not read check-runs for ${HEAD_SHA:0:9} (rc=$rc)"

# Legacy commit STATUSES are a separate surface from check-runs, and some
# required contexts arrive as statuses. Reading only one surface would report a
# present-and-green context as ABSENT and force a needless battery — noisy, not
# unsafe, but worth getting right.
STATUSES="$(gh api --paginate "repos/{owner}/{repo}/commits/${HEAD_SHA}/statuses" \
  --jq '.[] | {name: .context, status: "completed", conclusion: (if .state == "success" then "success" else .state end)}' 2>/dev/null | jq -s '.')"
rc=$?
(( rc == 0 )) || STATUSES='[]'

ALL="$(jq -s 'add' <<<"$CHECKS"$'\n'"$STATUSES" 2>/dev/null)"
[[ -n "$ALL" ]] || undecidable "could not merge the check surfaces"

MISSING="$(jq -r --argjson req "$REQUIRED_JSON" '
  [ $req[] as $r
    | { name: $r,
        state: ( [ .[] | select(.name == $r) ] | if length == 0 then "ABSENT"
                  else ( map(select(.status == "completed" and .conclusion == "success")) | if length > 0 then "ok" else "NOT-GREEN" end )
                  end ) }
    | select(.state != "ok") | "\(.name)=\(.state)" ]
  | join(", ")' <<<"$ALL" 2>/dev/null)"
rc=$?
(( rc == 0 )) || undecidable "could not evaluate required contexts against the check surfaces"

if [[ -n "$MISSING" ]]; then
  owed "required context(s) not present-and-green on ${HEAD_SHA:0:9}: ${MISSING}"
fi

# ---------------------------------------------------------------------------
# All four hold. Say what the skip does NOT cover, so it is visible rather than
# silent — the local run also executes suites that are not in the required set
# (that is how #8238 was found), and a silent skip would hide that.
# ---------------------------------------------------------------------------
say "NOTE: this skip covers the required shards only. The local battery also runs"
say "NOTE: non-required suites (repo-global ratchets, lint suites); those go unrun."
skippable "all ${REQUIRED_COUNT} required contexts present and green on ${HEAD_SHA:0:9}, tree clean, nothing unpushed, no apps/*/infra/** in the diff"
