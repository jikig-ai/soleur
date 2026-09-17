#!/usr/bin/env bash
# Decide whether `/ship` Phase 4 still owes a full local `test-all.sh` run.
#
# EXIT CONTRACT (the caller branches on this, never on the prose):
#   42  SKIPPABLE    — CI already verified this exact tree; running it again buys nothing
#    0  OWED         — run the battery
#    2  UNDECIDABLE  — could not determine; the caller MUST treat this as OWED
#   anything else    — an error; the caller MUST treat it as OWED
#
# ONLY 42 SKIPS, and the oddness of that number is the point. This script runs
# under `set -u`, and a reference to an unset variable aborts a non-interactive
# bash script with **exit status 1** (measured, bash 5.3.15). An earlier revision
# used 1 for SKIPPABLE and asserted in this very comment that "every failure path
# reaches 0 or 2, never 1" — so a single typo'd variable name in a future edit
# would have exited 1, the caller would have read SKIPPABLE, and a 35-minute
# safety run would have been deleted by a shell abort. `set -u` exists to catch
# that typo; routing it into the skip branch inverted it.
#
# 42 is outside every status bash produces by accident: 1 (set -u / generic
# failure), 2 (syntax), 126 (not executable), 127 (not found), 128+N (signal).
# Exit 2 remains a DISTINCT value so "the check could not run" is never silently
# folded into "the check says skip" — but the caller's rule is simply
# "not 42 ⇒ run", which is safe no matter how the script dies.
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
VERDICT_SKIPPABLE=42   # see the exit contract above: NOT 1, deliberately
VERDICT_UNDECIDABLE=2

say() { printf 'battery-owed: %s\n' "$*"; }

owed()        { say "OWED — $1";        exit "$VERDICT_OWED"; }
skippable()   { say "SKIPPABLE — $1";   exit "$VERDICT_SKIPPABLE"; }
undecidable() { say "UNDECIDABLE — $1 (caller must treat as OWED)"; exit "$VERDICT_UNDECIDABLE"; }

command -v git >/dev/null 2>&1 || undecidable "git not on PATH"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || undecidable "not inside a work tree"

# ---------------------------------------------------------------------------
# NO GROK-SPECIFIC ARM, and the reason is measured rather than argued.
#
# An earlier revision skipped unconditionally on the Grok harness, on the claim
# that `plugins/soleur/scripts/grok-pre-push-gate.sh` "re-runs test-all.sh at
# push time and ABORTS THE PUSH on failure", making Phase 4's run a duplicate.
# The second half of that claim is FALSE: the gate is not wired as a git hook.
# `lefthook.yml` has a `pre-push:` section and it carries zero references to that
# script (it is the client-pii-grep mirror); ship/SKILL.md's grok block is an
# INSTRUCTION TO AN AGENT, not an enforcement surface. So the arm traded a
# mechanism for a convention.
#
# Worse, it was evaluated BEFORE the conditions below and the script it looked
# for is always present in this repo — so on that harness it returned SKIPPABLE
# for every invocation, including a dirty tree and an infra diff. The suite's own
# Grok row pinned exactly that behaviour.
#
# The framing was also inverted: Phase 4 is the FIRST local run and the push-time
# gate is the second, so skipping Phase 4 does not remove a duplicate — it moves
# the only local checkpoint PAST Phase 5's checklist and Phase 5.5's
# code-mutating gates, so a red at push time invalidates all of that work.
#
# The CI-based conditions below already cover the Grok re-run path once the
# branch is pushed, and they cover it with EVIDENCE (a green required set on this
# exact sha) rather than a prediction about what a later phase will do.

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

HEAD_SHA="$(git rev-parse HEAD 2>/dev/null)"
[[ "$HEAD_SHA" =~ ^[0-9a-f]{40}$ ]] || undecidable "could not resolve a full HEAD sha"

# NO SEPARATE "IS IT PUSHED?" CONDITION, deliberately.
#
# An earlier revision fetched origin/<branch> and refused on a non-zero unpushed
# count. That is SUBSUMED by condition 3: an unpushed commit has no check-runs
# for its sha, so every required context reads ABSENT and the gate already
# returns OWED. There is no tree the unpushed check refused that condition 3
# admits — and its two test rows passed only because the `gh` stub ignored the
# sha it was asked about, so it pinned nothing.
#
# Where the two DISAGREE, the unpushed check was wrong: a commit pushed under a
# different ref name, or a locally stale origin/<branch>, is a tree CI genuinely
# verified, and refusing it bought a needless 35-minute run. It also made a
# network write (`git fetch`) inside a read-only-looking gate, whose failure
# returned UNDECIDABLE — so a flaky link cost a battery.

# ---------------------------------------------------------------------------
# Condition 2 — the infra shard, where this battery is the ONLY BLOCKING gate.
#
# `apps/web-platform/infra/`'s registered suites are run by
# .github/workflows/infra-validation.yml on every PR touching the path, but that
# workflow is NOT in the required set (#6480) — so nothing stops
# `gh pr merge --auto` on a red one. "Only BLOCKING gate", not "only gate": the
# overstated version is what gets a condition deleted by the next person to check
# it, and the narrower claim is still enough to justify refusing here.
#
# TWO PREFIXES, because test-all.sh matches two (scripts/test-all.sh, the
# `_infra_in_diff` block). The second is not decoration: apex-single-node-replace
# reads apply-web-platform-infra.yml's `-target=` allow-list, so a diff dropping
# an entry from that workflow ALONE is an infra regression. An earlier revision
# re-derived the predicate with one prefix and drifted on its first write; the
# parity row in the suite now fails if test-all.sh grows a third.
#
# SELF-RETIRING: evaluated only while `infra-validate-required` is absent from
# the LIVE required set. When #6480 lands and that context becomes required,
# condition 3 demands it present-and-green on this sha and this condition becomes
# a no-op automatically — no stale pointer, no dead branch, and nobody has to
# remember to come back. That is the same reasoning as reading the live ruleset
# rather than scripts/required-checks.txt, applied one level up.
# ---------------------------------------------------------------------------
if ! git rev-parse --verify --quiet refs/remotes/origin/main >/dev/null 2>&1; then
  undecidable "origin/main is unresolvable; cannot scope the diff"
fi
CHANGED="$(git diff --name-only origin/main...HEAD 2>/dev/null)"
rc=$?
(( rc == 0 )) || undecidable "could not compute the branch diff (rc=$rc)"
INFRA_RE='^(apps/web-platform/infra/|\.github/workflows/apply-web-platform-infra\.yml$)'

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

# EVERY NETWORK CALL IS BOUNDED. `gh` imposes no timeout of its own: measured
# against a blackholed endpoint, `gh api --hostname 10.255.255.1 …` was still
# running at 25 s. Three unbounded calls in a gate that runs before a 35-minute
# battery is the "never throws AND always returns" rule with only the first half
# satisfied — try/catch bounds exceptions, not time. rc 124 from `timeout` needs
# no special handling: it is non-zero, so each call falls into the branch it
# already has (undecidable for the first two, an empty set for statuses).
REQUIRED_JSON="$(timeout 15 gh api 'repos/{owner}/{repo}/rules/branches/main' \
  --jq '[.[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context]' 2>/dev/null)"
rc=$?
(( rc == 0 )) || undecidable "could not read the branch ruleset (rc=$rc)"

REQUIRED_COUNT="$(jq 'length' <<<"$REQUIRED_JSON" 2>/dev/null)"
[[ "$REQUIRED_COUNT" =~ ^[0-9]+$ ]] || undecidable "could not parse the required-context list"
(( REQUIRED_COUNT > 0 )) || undecidable "the ruleset declares zero required contexts; refusing to skip on an empty requirement set"

# --paginate is load-bearing, and NOT for the reason first written here. The API
# defaults to 30 per page but `gh` injects `per_page=100` automatically (measured
# via GH_DEBUG=api, gh 2.101.0), so the page count is total/100. That still
# paginates on this repo: measured over six recent origin/main commits, check-run
# rows ranged 73–227 (a57cdb772 = 227 rows / 97 distinct names / 3 pages /
# 3.3–4.4 s).
#
# DO NOT cap the pagination. The `sort_by(.started_at) | last` evaluation below
# genuinely needs every attempt per name — truncating at page 1 on a 227-row sha
# hands it an arbitrary subset and it could pick a stale "newest". The bound is
# the `timeout`, not a page cap. The set is self-limiting anyway (the API
# defaults to filter=latest, so rows scale with distinct checks × re-runs).
CHECKS="$(timeout 30 gh api --paginate "repos/{owner}/{repo}/commits/${HEAD_SHA}/check-runs" \
  --jq '.check_runs[] | {name: .name, status: .status, conclusion: .conclusion}' 2>/dev/null | jq -s '.')"
rc=$?
(( rc == 0 )) || undecidable "could not read check-runs for ${HEAD_SHA:0:9} (rc=$rc)"

# Legacy commit STATUSES are a separate surface from check-runs, and some
# required contexts can arrive as statuses. But measured over six recent
# origin/main commits this endpoint returned ZERO rows every time — all 26
# required contexts on this repo are check-runs — while costing ~629 ms per
# invocation. So it is fetched LAZILY: only when the check-runs surface alone
# leaves a context unaccounted for.
#
# That removes a round trip from the SKIPPABLE path specifically, which is the
# one path where this gate's latency is pure overhead (no battery follows it to
# amortize against). On the OWED path the call still runs and still does real
# work — distinguishing ABSENT from present-as-a-status — where 0.6 s sits
# against 35 minutes.
eval_missing() {
  jq -r --argjson req "$REQUIRED_JSON" '
    [ $req[] as $r
      | { name: $r,
          state: ( [ .[] | select(.name == $r) ]
                   | sort_by(.started_at // "")
                   | last
                   | if . == null then "ABSENT"
                     elif (.status == "completed" and .conclusion == "success") then "ok"
                     else "NOT-GREEN"
                     end ) }
      | select(.state != "ok") | "\(.name)=\(.state)" ]
    | join(", ")' <<<"$1" 2>/dev/null
}

MISSING="$(eval_missing "$CHECKS")"
rc=$?
(( rc == 0 )) || undecidable "could not evaluate required contexts against the check surfaces"

if [[ -n "$MISSING" ]]; then
  STATUSES="$(timeout 15 gh api --paginate "repos/{owner}/{repo}/commits/${HEAD_SHA}/statuses" \
    --jq '.[] | {name: .context, status: "completed", conclusion: (if .state == "success" then "success" else .state end), started_at: .created_at}' 2>/dev/null | jq -s '.')"
  rc=$?
  (( rc == 0 )) || STATUSES='[]'
  ALL="$(jq -s 'add' <<<"$CHECKS"$'\n'"$STATUSES" 2>/dev/null)"
  [[ -n "$ALL" ]] || undecidable "could not merge the check surfaces"
  MISSING="$(eval_missing "$ALL")"
  rc=$?
  (( rc == 0 )) || undecidable "could not evaluate required contexts against the check surfaces"
fi

# NEWEST RUN PER NAME, never "any run with this name was green".
#
# GitHub keeps every attempt, and a re-run adds a row rather than replacing one:
# measured on merge commit 72fdff382 of this repo, 121 check-runs carried only 63
# distinct names (`probe` x14, `connector_census` x13). So an `any(...succeeded)`
# test reports `ok` for a context that passed, was RE-RUN, and FAILED — which is
# the exact state a human would look at and call red. Sort by started_at and
# judge only the last one; GitHub's own rule is latest-run-wins.
#
# `completed`+`success` is still required, so a name whose newest attempt is
# still running reads NOT-GREEN rather than inheriting an older green.

if [[ -n "$MISSING" ]]; then
  owed "required context(s) not present-and-green on ${HEAD_SHA:0:9}: ${MISSING}"
fi

# Condition 2, evaluated here because it is predicated on the LIVE required set.
if ! jq -e --arg c "infra-validate-required" 'index($c) != null' <<<"$REQUIRED_JSON" >/dev/null 2>&1; then
  if printf '%s\n' "$CHANGED" | grep -qE "$INFRA_RE"; then
    owed "diff touches the infra surface and infra-validate-required is NOT in the live required set (#6480) — the battery is its only BLOCKING gate"
  fi
fi

# ---------------------------------------------------------------------------
# All four hold. Say what the skip does NOT cover, so it is visible rather than
# silent — the local run also executes suites that are not in the required set
# (that is how #8238 was found), and a silent skip would hide that.
# ---------------------------------------------------------------------------
# No "and these suites go unrun" note here, deliberately: it would be FALSE.
# test-all.sh registers every suite inside one of want_scripts / want_bun /
# want_webplat / want_infra, and CI's required `test` context runs the first
# three plus web-platform-build. The only local-only residue is the infra group,
# which condition 2 refuses on. An earlier revision claimed a residue that does
# not exist, which both overstated the risk and contradicted this file's own
# containment argument.
skippable "all ${REQUIRED_COUNT} required contexts present and green on ${HEAD_SHA:0:9}, tree clean, nothing unpushed, no apps/*/infra/** in the diff"
