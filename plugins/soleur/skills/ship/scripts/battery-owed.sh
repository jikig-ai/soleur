#!/usr/bin/env bash
# Decide whether `/ship` Phase 4 still owes a local `test-all.sh` run.
#
# EXIT CONTRACT (the caller branches on this, never on the prose):
#   42  SKIPPABLE    — CI already verified this exact tree; running it again buys nothing,
#                     OR the operator declared CI the gate (`ci-is-the-gate` token, below)
#    0  OWED         — run the gate. Since #8322 that means `--affected` by
#                     default; the FULL local battery is opt-in via
#                     `/ship --full` (operator) → `test-all.sh --full`
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
# test-webplat + test-bun + test-scripts + test-scripts-heavy + web-platform-build,
# of which the first four are the same `test-all.sh` shards this battery runs —
# on the pushed head. The skill also mandates re-running the battery after any post-Phase-4
# change (a review fix, a main sync, an advisor fix), and on that re-run path the
# work is frequently a pure duplicate. Measured on PR #8233: two full batteries, ~70 min, the second
# finishing against a head whose 26/26 required checks were already green on the
# identical SHA. It could not have changed the merge decision.
#
# WHAT THIS IS NOT. It does not make CI the local fail-fast checkpoint and it
# weakens no merge gate. At FIRST run Phase 4 precedes the Phase 6 push, so
# there is usually no CI for HEAD and this returns OWED — by design. The saving
# is concentrated on the re-run path, which is where the duplicate cost lives.
#
# OPERATOR INTENT (2026-11-06). A brief that says "rely on CI's required test check" produced a ~45-minute local battery
# anyway, because this script read CI state and never intent. A bullet `- ci-is-the-gate: <words>` under a level-2
# `## Operator Constraints` heading in the CURRENT branch's knowledge-base/project/specs/<branch>/session-state.md (working
# tree only, never origin/*) now makes this return 42 without CI evidence: conditions 1 (dirty tree), 2 (behind main) and 4
# (CI state) stand down for it. It NEVER overrides the infra surface (committed, staged or untracked; the local infra shard
# is its only blocking gate, #6480), an unmeasurable diff or a merge in progress, and `/ship --full` outranks it (the
# caller checks that first). Standalone runs (no one-shot): the operator may add the bullet by hand; nothing else should.
# TRUST: the token is a hint the same commit can write. What bounds a planted or wrong token is outside the commit: the live
# branch ruleset (required `test` context, merge queue) still gates every merge, the arm's infra refusal, and the verdict
# line printing the words, so a planted token is visible in the transcript and the PR Test plan. The words are untrusted
# text: cut at 200 bytes, then only [A-Za-z0-9 ,.-] survive. Any HTML comment marker or unrecognised fence line in the
# file voids the token (fail closed), fenced code is skipped, the file must hold exactly ONE `## Operator Constraints`
# section, and a symlinked file or directory reads no token. A branch name holding `/` reads the
# nested path specs/<a>/<b>/session-state.md. The committed diff is the gate; the working-tree sources are defence in depth,
# and per-file index flags (assume-unchanged, skip-worktree) are operator-local state, bounded by the merge queue.
# Writer contract: skills/one-shot/references/operator-constraints.md.
# CONSUMERS (#12247): ship Phase 4 calls this with NO argument (token, then CI evidence). Work Phase 2, review's lead gate and the
# Grok pre-push gate call `--token-only`: no valid token is OWED at once with no CI state read; a valid token runs the arm above
# unchanged. Any other argument is UNDECIDABLE. Work and review reach it through scripts/gate-or-skip.sh; test-fix-loop and the
# lefthook bun-test hook never read it (a fix loop must run tests; the hook is tracked in #12297).
set -uo pipefail

VERDICT_OWED=0
VERDICT_SKIPPABLE=42   # see the exit contract above: NOT 1, deliberately
VERDICT_UNDECIDABLE=2

# Strip C0 controls, DEL and the Unicode line separators before printing.
# Check-run names come from workflow YAML — which, on a PR, arrives IN THE DIFF
# UNDER REVIEW — and ruleset context strings come from repo admin config. Neither
# is trusted to be single-line: a newline inside one forges a second
# `battery-owed: …` line in the transcript, and the obvious thing to forge is a
# SKIPPABLE verdict. The exit code is unaffected (and SKILL.md branches on it),
# but a forged line sitting beside the caller's own echo is worth denying.
#
# Shared context-sanitize lib (#10395), three levels up at scripts/lib/. When it
# is unreadable the same-name fallback carries this site's pre-change strip set
# (C0+DEL plus the LS/PS sed) — never weaker than today.
_ctx_lib="$(cd "${BASH_SOURCE[0]%/*}/../../../scripts/lib" 2>/dev/null && pwd -P)/context-sanitize.sh"
_ctx_lib="${_ctx_lib:-/nonexistent/context-sanitize.sh}"
# shellcheck source=/dev/null
[[ -r "$_ctx_lib" ]] && . "$_ctx_lib" || true
declare -F soleur_ctx_sanitize >/dev/null 2>&1 \
  || soleur_ctx_sanitize() { LC_ALL=C tr -d '\000-\037\177' | LC_ALL=C sed $'s/\xe2\x80\xa8//g; s/\xe2\x80\xa9//g'; }
_sanitize() { printf '%s' "$*" | soleur_ctx_sanitize; }
say() { printf 'battery-owed: %s\n' "$(_sanitize "$*")"; }

owed()        { say "OWED — $1";        exit "$VERDICT_OWED"; }
skippable()   { say "SKIPPABLE — $1";   exit "$VERDICT_SKIPPABLE"; }
undecidable() { say "UNDECIDABLE — $1 (caller must treat as OWED)"; exit "$VERDICT_UNDECIDABLE"; }

# The one accepted argument is `--token-only` (#12247); anything else, including a second argument, is UNDECIDABLE.
TOKEN_ONLY=0
if (( $# == 1 )) && [[ "$1" == "--token-only" ]]; then TOKEN_ONLY=1
elif (( $# > 0 )); then undecidable "unknown argument (the only accepted flag is --token-only)"; fi

command -v git >/dev/null 2>&1 || undecidable "git not on PATH"
# An inherited git-location variable (a hook's GIT_DIR / GIT_INDEX_FILE) would redirect every read below.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || undecidable "not inside a work tree"

# --- operator token (see OPERATOR INTENT in the header) -------------------------------------------------------------
# Bytes, not locale characters (LC_ALL=C). Fenced code is skipped (CommonMark rules: an opener is 3+ backticks or tildes
# indented at most 3 spaces, a closer is the same character, at least as long, nothing else on the line); a fence-looking
# line the rule does not recognise (blockquoted, indented 4+) and ANY `<!--` or `-->` voids the token, so a quoted or
# hidden copy of the section fails closed. The section ends at the first non-bullet line, at a blank line after a bullet,
# and at any `#` heading; a SECOND `## Operator Constraints` section voids the token (n must be 1), so text appended later
# cannot become one. The filter runs BEFORE the emptiness test, so whitespace-only, control-only or non-ASCII-only words
# are no token. The reader prints only the matching line; a symlinked file or directory is not read at all.
# Accepted: only comment markers void the token, so a section inside another invisible HTML block (<style>, <pre>) still reads; the file is pipeline-written, and the infra refusal still stands.
OPERATOR_CI_WORDS=""
_br="$(git branch --show-current 2>/dev/null)"
_tp="$(cd "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null && pwd -P)"
_ss="${_tp}/knowledge-base/project/specs/${_br}/session-state.md"
_sd="$(cd "${_ss%/*}" 2>/dev/null && pwd -P)"
if [[ -n "$_br" && -n "$_tp" && "$_sd" == "${_ss%/*}" && -f "$_ss" && ! -L "$_ss" ]]; then
  OPERATOR_CI_WORDS="$(LC_ALL=C awk '
    function runlen(t, c,   i) { for (i = 1; substr(t, i, 1) == c; i++); return i - 1 }
    /<!--|-->/ { bad = 1; next }
    f { t = $0; if (t ~ /^    /) next; sub(/^ */, "", t); sub(/[ \t]+$/, "", t)
        if (length(t) >= fl && runlen(t, fc) == length(t)) f = 0; next }
    { t = $0
      if (t !~ /^    /) { u = t; sub(/^ */, "", u); c = substr(u, 1, 1)
        if ((c == "`" || c == "~") && runlen(u, c) >= 3) { f = 1; fc = c; fl = runlen(u, c); next } } }
    /^[ \t>]*(```|~~~)/ { bad = 1; next }
    /^#+[[:space:]]/ { s = ($0 == "## Operator Constraints"); b = 0; if (s) n++; next }
    s && /^[[:space:]]*$/ { if (b) s = 0; next }
    s && !/^- / { s = 0; next }
    s { b = 1 }
    s && !w && /^- ci-is-the-gate:[[:space:]]+[^[:space:]]/ { w = $0; sub(/^- ci-is-the-gate:[[:space:]]+/, "", w); w = substr(w, 1, 200) }
    END { if (n == 1 && !bad && w != "") print w }' "$_ss" 2>/dev/null \
    | LC_ALL=C tr -cd "A-Za-z0-9 ,.-")"
  [[ -n "${OPERATOR_CI_WORDS//[[:space:]]/}" ]] || OPERATOR_CI_WORDS=""
fi
# `--token-only`: no valid token is OWED right here, before any CI state, ruleset or origin/main read (#12247).
(( TOKEN_ONLY )) && [[ -z "$OPERATOR_CI_WORDS" ]] && owed "--token-only: no operator ci-is-the-gate token (CI state is not consulted at this site)"

# ---------------------------------------------------------------------------
# NO GROK-SPECIFIC ARM, and the reason is measured rather than argued.
# (Scope, #12247: this rejects a harness-keyed arm. The operator-intent token waiving the Grok pre-push gate's affected step
# is a different channel; its residuals are recorded in the ADR-242 2026-11-07 amendment.)
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
# Condition 1 — the working tree must BE the HEAD commit.
#
# This is the sharpest of the four. A green run on an ancestor SHA is not
# evidence about your working tree, and nothing downstream can recover from
# getting it wrong: every later condition would be measuring a different tree
# than the one about to be shipped.
# ---------------------------------------------------------------------------
DIRTY="$(git status --porcelain 2>/dev/null)"
rc=$?
(( rc == 0 )) || undecidable "git status failed (rc=$rc)"
[[ -n "$DIRTY" && -z "$OPERATOR_CI_WORDS" ]] && owed "working tree is dirty; CI verified a different tree"

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
# Condition 2 — THE BRANCH MUST BE UP TO DATE WITH origin/main.
#
# This is what makes the gate's headline claim TRUE, and without it the claim is
# false on this repo. `.github/workflows/ci.yml` triggers on `push` for **main
# only**, plus `pull_request` — so a feature branch gets no push-event CI at all,
# and the `test` check-run on its head comes from a pull_request run, which
# GitHub builds against `refs/pull/N/merge`. CI therefore verified
# merge(HEAD, base-at-run-time), NOT the HEAD tree the local battery would run.
#
# Those two trees are identical exactly when origin/main is already an ancestor of
# HEAD: the merge is then a fast-forward and its tree IS HEAD's tree. When main
# has advanced they differ, and "CI verified this exact tree" stops being true —
# which is ordinary rather than exotic: the CI Required ruleset is `strict: true`
# (measured 2026-09-18; it read `false` when this was first written), so a branch
# cannot MERGE while behind — but it is routinely behind while its CI runs and
# while this gate is consulted, which is exactly when the two trees differ.
#
# Refusing here rather than reasoning about whether the merge tree is "close
# enough" keeps the gate's claim and its evidence the same sentence. The cost is
# that a behind branch runs the battery — which is the status quo, not a
# regression.
# ---------------------------------------------------------------------------
if [[ -z "$OPERATOR_CI_WORDS" ]] && ! git merge-base --is-ancestor refs/remotes/origin/main HEAD 2>/dev/null; then
  owed "origin/main is not an ancestor of HEAD; CI's pull_request run verified merge(HEAD, base), not this tree"
fi

# ---------------------------------------------------------------------------
# Condition 3 — the infra shard, where this battery is the ONLY BLOCKING gate.
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
  undecidable "${OPERATOR_CI_WORDS:+operator ci-is-the-gate set but }origin/main is unresolvable; cannot scope the diff"
fi
# The operator-token arm below builds its path lists the same way, for the same reasons: NUL-delimited so a C-quoted name
# reaches INFRA_RE as raw bytes, `--no-renames` so a rename lists BOTH its old and its new path (a rename-detected diff prints
# only the new one), `--ignore-submodules=none` so a gitlink is not hidden by configuration, and `git -C` the repo top (`_tp`,
# resolved above once the work-tree check passed) because `diff.relative` limits a diff to the cwd subtree.
# `core.quotePath=false` alone is NOT a fix: it governs only bytes at or above 0x80; a tab, `"` or `\` stays quoted.
# A copy needs no handling (its source is never listed in either form). `tr` re-splits a name that holds a newline: the extra
# lines can only add a false OWED, never hide a real infra path (its first line still starts at the prefix). T5f and T5h pin
# the rename members (dropping `--no-renames` reddens both); T20 pins the rest.
CHANGED="$(git -C "${_tp:-.}" diff -z --no-renames --ignore-submodules=none --name-only refs/remotes/origin/main...HEAD -- 2>/dev/null | tr '\0' '\n')"
rc=$?
(( rc == 0 )) || undecidable "${OPERATOR_CI_WORDS:+operator ci-is-the-gate set but }could not compute the branch diff (rc=$rc)"
# An EMPTY diff is not "no infra paths" — it is "HEAD is an ancestor of
# origin/main" (already merged, or origin/main fetched past the branch point), in
# which case condition 2 is a no-op regardless of what the branch touched.
if [[ -z "${CHANGED//[[:space:]]/}" ]] && ! git merge-base --is-ancestor HEAD refs/remotes/origin/main 2>/dev/null; then
  undecidable "${OPERATOR_CI_WORDS:+operator ci-is-the-gate set but }the branch diff is empty but HEAD is not an ancestor of origin/main; cannot scope the infra check"
fi
# INFRA_RE is deliberately NARROWER than infra-validation.yml's trigger set (#12332): it tracks what the LOCAL infra shard
# can test (apps/web-platform/infra/run-registered-suites.sh globs only apps/web-platform/infra/) plus the apply workflow;
# widening it would demand a local battery that cannot exercise the added paths. The wider trigger set is #6480's concern.
INFRA_RE='^(apps/web-platform/infra/|\.github/workflows/apply-web-platform-infra\.yml$)'

# The operator-token arm. Condition 1 no longer guarantees a clean tree, so it builds its OWN path list from four
# NUL-delimited, rename-free sources: the committed diff, tracked working-tree changes, staged changes (a path staged then
# deleted from disk shows only here), and untracked files. NUL-delimited because git C-quotes a path holding a non-ASCII
# byte, a tab, `"` or `\` (`"apps/web-platform/infra/\303\251.tf"`), which the `^`-anchored INFRA_RE then misses;
# `--no-renames` lists both the old and the new path of a rename; `git -C "$_top"` makes the untracked listing repo-wide
# whatever the cwd; `refs/remotes/origin/main` cannot be shadowed by a tag or branch of the same short name. The sources share
# one failure exit. The grep runs on the paths PLUS one sentinel infra path, so a here-string or pipe that silently
# fails (count 0) cannot read as "no infra match". It runs its OWN INFRA_RE grep: the existing refusal sits after condition
# 4 and needs REQUIRED_JSON, which this exit skips. Its infra refusal does not self-retire like condition 4's. A merge in
# progress or an unmerged path is refused: the tree is not a state anyone reviewed.
if [[ -n "$OPERATOR_CI_WORDS" ]]; then
  _top="$(git rev-parse --show-toplevel 2>/dev/null)" \
    && _un="$(git -C "$_top" ls-files -u)" \
    && _w1="$(git -C "$_top" diff -z --no-renames --ignore-submodules=none --name-only refs/remotes/origin/main...HEAD -- | tr '\0' '\n')" \
    && _w2="$(git -C "$_top" diff -z --no-renames --ignore-submodules=none --name-only HEAD -- | tr '\0' '\n')" \
    && _w3="$(git -C "$_top" ls-files -z -o --exclude-standard | tr '\0' '\n')" \
    && _w4="$(git -C "$_top" diff -z --no-renames --ignore-submodules=none --name-only --cached HEAD -- | tr '\0' '\n')" \
    || undecidable "operator ci-is-the-gate set but the working-tree scope check failed"
  if [[ -n "$_un" ]] || git -C "$_top" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 \
     || [[ -e "$(git -C "$_top" rev-parse --absolute-git-dir)/MERGE_HEAD" ]]; then
    owed "operator ci-is-the-gate set, but a merge is in progress or paths are unmerged"
  fi
  _all="${_w1}"$'\n'"${_w2}"$'\n'"${_w3}"$'\n'"${_w4}"
  _n="$(printf '%s\n%s\n' "$_all" 'apps/web-platform/infra/__sentinel__' | grep -cE "$INFRA_RE")"
  [[ "$_n" =~ ^[0-9]+$ ]] && (( _n >= 1 )) || undecidable "operator ci-is-the-gate set but the infra scope check did not run"
  (( _n > 1 )) && owed "operator ci-is-the-gate set, but the diff touches the infra surface (no required CI check, #6480): the local infra shard is its only BLOCKING gate"
  skippable "operator declared CI the gate (untrusted text from session-state.md: ${OPERATOR_CI_WORDS}): local battery NOT executed; this script read no CI state. Record in the PR Test plan: local battery NOT executed per operator constraint; operator declared CI test the gate"
fi

# ---------------------------------------------------------------------------
# Condition 4 — every required context PRESENT and green on this exact SHA.
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
# `timeout` is coreutils and is NOT present on a stock macOS. Without this guard
# the calls below exit 127 and land in the ruleset branch, which then blames
# GitHub for a missing binary — and on that host the gate is permanently
# UNDECIDABLE, so the feature silently never works. This ships to customers'
# machines, where macOS-without-coreutils is the common case.
command -v timeout >/dev/null 2>&1 || undecidable "timeout (coreutils) not on PATH; cannot bound the API calls"

# EVERY NETWORK CALL IS BOUNDED. `gh` imposes no timeout of its own: measured
# against a blackholed endpoint, `gh api --hostname 10.255.255.1 …` was still
# running at 25 s. Three unbounded calls in a gate that runs before a 35-minute
# battery is the "never throws AND always returns" rule with only the first half
# satisfied — try/catch bounds exceptions, not time. rc 124 from `timeout` needs
# no special handling: it is non-zero, so each call falls into the branch it
# already has (undecidable for the first two, an empty set for statuses).
# {context, integration_id} — NOT the context alone. GitHub only counts a
# check-run toward a required context when it comes from the app that context
# pins, so matching on name alone made this gate strictly MORE PERMISSIVE than
# the ruleset it calls authoritative — the unsafe direction: any installed app
# with `checks: write` could satisfy a required context by naming a check-run
# after it.
#
# Carry each context's OWN integration_id; do NOT collapse this to a constant.
# The app id is NOT uniform across the required set. Measured 2026-09-17 against
# the live ruleset. Today (post-#9454, merge queue adopted, CodeQL advisory) every
# required context is pinned to 15368 (GitHub Actions) — 23 CI Required + 2 CLA
# Required — but that is a property of the current rulesets, not of this gate. While
# CodeQL WAS required (until #9454) the split was 25 x 15368 + `CodeQL` x 57789
# (github-advanced-security), and a CodeQL re-tighten (codeql-1537-revisit-watch.yml)
# would restore a non-uniform set. The code is deliberately per-context so it stays
# right either way; an earlier revision of this comment asserted a uniform 15368 set
# and was wrong at the time. Hardcoding 15368 would leave any differently-bound
# context permanently unmatched → ABSENT → OWED.
# --paginate here too. Without it a rules array exceeding one page truncates and
# the gate requires FEWER contexts than the ruleset does — under-requiring, the
# unsafe direction, and the same failure this file rejects required-checks.txt
# for. The union across every ruleset on the branch is deliberate: the CLA and CI
# rulesets each contribute contexts.
REQUIRED_JSON="$(timeout 15 gh api --paginate 'repos/{owner}/{repo}/rules/branches/main' \
  --jq '.[] | select(.type == "required_status_checks") | .parameters.required_status_checks[] | {context: .context, integration_id: .integration_id}' 2>/dev/null | jq -s '.')"
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
  --jq '.check_runs[] | {name: .name, status: .status, conclusion: .conclusion, started_at: .started_at, app_id: (.app.id // null)}' 2>/dev/null | jq -s '.')"
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
      | { name: $r.context,
          state: ( [ .[]
                     | select(.name == $r.context)
                     # App identity: a required context pinned to an integration
                     # is satisfiable ONLY by that app. A row with no app id (a
                     # legacy commit status) can satisfy an UNPINNED context only.
                     | select($r.integration_id == null or .app_id == $r.integration_id) ] as $rows
                   # ORDER-INDEPENDENT REFUSALS FIRST. `sort_by(.started_at // "")`
                   # gives a null/absent started_at the key "", which sorts BEFORE
                   # every ISO timestamp — so `last` picks an OLDER completed row
                   # and an in-flight attempt becomes invisible. Measured: one
                   # completed+success row plus one in_progress row with
                   # started_at null returned "ok". That is a wrong SKIP, and it
                   # is the same newest-wins inversion this file already fixed
                   # once, arriving through the sort KEY instead of the sort.
                   #
                   # So neither refusal below consults ordering at all. Any
                   # non-completed attempt means CI is not finished on this sha,
                   # whatever its timestamp. And when two or more rows exist with
                   # a missing key, "newest" is not decidable — fail toward OWED
                   # rather than pick one. A single completed row needs no order.
                   | if ($rows | length) == 0 then "ABSENT"
                     elif ($rows | any(.status != "completed")) then "NOT-GREEN"
                     elif (($rows | length) > 1
                           and ($rows | any((.started_at // "") == ""))) then "NOT-GREEN"
                     else ($rows
                           | sort_by(.started_at)
                           | last
                           | if .conclusion == "success" then "ok" else "NOT-GREEN" end)
                     end ) }
      | select(.state != "ok") | "\(.name)=\(.state)" ]
    | join(", ")' <<<"$1" 2>/dev/null
}

MISSING="$(eval_missing "$CHECKS")"
rc=$?
(( rc == 0 )) || undecidable "could not evaluate required contexts against the check surfaces"

if [[ -n "$MISSING" ]]; then
  STATUSES="$(timeout 15 gh api --paginate "repos/{owner}/{repo}/commits/${HEAD_SHA}/statuses" \
    --jq '.[] | {name: .context, status: "completed", conclusion: (if .state == "success" then "success" else .state end), started_at: .created_at, app_id: null}' 2>/dev/null | jq -s '.')"
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
# `any(.[]; .context == $c)`, not `index($c)`: REQUIRED_JSON is an array of
# {context, integration_id} OBJECTS, so a bare-string index never matches and the
# condition would never retire.
if ! jq -e --arg c "infra-validate-required" 'any(.[]; .context == $c)' <<<"$REQUIRED_JSON" >/dev/null 2>&1; then
  # The grep runs on the paths PLUS one sentinel infra path (as in the token arm): a here-string or pipe that silently fails
  # (a full TMPDIR for a large list) would otherwise read as "no infra match" and fall through to SKIPPABLE.
  _n461="$(printf '%s\n%s\n' "$CHANGED" 'apps/web-platform/infra/__sentinel__' | grep -cE "$INFRA_RE")"
  [[ "$_n461" =~ ^[0-9]+$ ]] && (( _n461 >= 1 )) || undecidable "${OPERATOR_CI_WORDS:+operator ci-is-the-gate set but }the infra scope check did not run"
  if (( _n461 > 1 )); then
    owed "diff touches the infra surface and infra-validate-required is NOT in the live required set (#6480) — the battery is its only BLOCKING gate"
  fi
fi

# ---------------------------------------------------------------------------
# Every condition held.
# ---------------------------------------------------------------------------
# No "and these suites go unrun" note here, deliberately: it would be FALSE.
# test-all.sh registers every suite inside one of want_scripts /
# want_scripts_heavy / want_bun / want_webplat / want_infra, and CI's required
# `test` context runs the first four plus web-platform-build. The only
# local-only residue is the infra group,
# which condition 2 refuses on. An earlier revision claimed a residue that does
# not exist, which both overstated the risk and contradicted this file's own
# containment argument.
# STATE ONLY WHAT WAS MEASURED. An earlier revision of this line claimed
# "nothing unpushed" — a predicate this script no longer evaluates at all — and
# "no apps/*/infra/** in the diff", which is FALSE on the self-retire path, where
# the infra block is skipped precisely because the context became required and
# the diff may well touch infra. A verdict line naming a cause the run did not
# measure is the AP-021 class, and it is worse here than elsewhere because this
# line is the operator's only record of why 35 minutes were skipped.
skippable "all ${REQUIRED_COUNT} required contexts present and green on ${HEAD_SHA:0:9}; working tree clean; origin/main is an ancestor of HEAD"
