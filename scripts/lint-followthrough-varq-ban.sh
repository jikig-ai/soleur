#!/usr/bin/env bash
# lint-followthrough-varq-ban.sh -- the follow-through PROBE lint. Four rules, one exit
# contract. Rule 1 (#6757): no probe may gate its exit on the banned `: "${VAR:?msg}"` /
# colon-less `${VAR?msg}` word-expansion. Rule 2 (#7946): no file under the target dir may
# name the retired credential. Rule 3 (#7490): every repo-relative path a probe assigns must
# exist in the checkout. The name is kept although the file now does more than rule 1: it is
# cited from followthrough-convention.md, ADR-031, the Article 30 register and several
# learnings, and renaming it would churn point-in-time records.
#
# RULE 1 (#6757) -- the BANNED WORD-EXPANSION BAN. Rules 2 and 3 carry headings in both the
# header and the body; rule 1 did not, so a reader looking for it found it only via the summary
# line above.
#
# WHY: under the sweeper's non-interactive shell, `${VAR:?}` / `${VAR?}` ABORTS with
# status 1 the instant the variable is unset/empty. In the sweep-followthroughs.sh exit
# contract `exit 1 = FAIL = "do NOT close"`, so an unprovisioned secret posts a DAILY
# false-FAIL comment forever instead of exiting 2 (TRANSIENT = quiet retry). The
# compliant form is `if [[ -z "${VAR:-}" ]]; then echo "TRANSIENT: ..." >&2; exit 2; fi`.
# The ban is documented in followthrough-convention.md §Author workflow; this guard is
# its mechanical enforcer. It is the EXECUTABLE FORM of that doc's canonical census.
#
# Detection = the canonical census, byte-faithful:
#   grep -nE '\$\{[A-Za-z_][A-Za-z0-9_]*:?\?'  (optional colon, then literal `?`)
# then drop FULL-LINE comments (`^[0-9]+:[[:space:]]*#` on the -n output). Any surviving
# line is a violation. The regex is named-var only by design (matches the doc census);
# a positional-param `${1:?}` is uncaught, but every probe secret is a named var.
#
# LINE-NUMBER ORDER IS LOAD-BEARING: run `grep -n` on the RAW file FIRST, then drop
# full-line-comment hits. Piping `grep -v '^#' | grep -n` re-indexes line numbers against
# the comment-stripped stream and mis-cites every offender (ghcr-minter-live's real line 28
# would print as 4). Detection is identical either way; only the diagnostic file:line differs,
# and naming the offender accurately is the whole value of the guard.
#
# RULE 2 (#7946) -- the RETIRED CREDENTIAL NAME BAN. No file under the target dir -- any name,
# any depth, executable line or comment -- may name `SENTRY_AUTH_TOKEN`. That is the
# canonical Sentry env-var name, so a workstation `doppler run -c prd_terraform` binds a
# PERSONAL, human-account-scoped token under it silently (#7797); the followthroughs consume
# `SENTRY_ACTIONS_RO_TOKEN`, an org-level read-only integration (ADR-031), which no Doppler
# config can satisfy by accident. Rule 2 deliberately does NOT apply rule 1's two exemptions:
# it reads `.test.sh` and every other file (an env stub or a fixture is what the next author
# copies) and it does NOT strip comments (a name in a comment is what the next author copies).
# It has its OWN scanned counter (`scanned_rule2`, the file count under the dir) and its own
# floor, so a broken rule-2 walk cannot hide behind rule 1's count -- and vice versa. Same
# exit contract.
#
# RULE 3 (#7490) -- the PROBE REPO-PATH EXISTENCE check. Every assignment-shaped (or
# `source`-shaped) repo-relative path literal in a non-test probe must name an artefact that
# EXISTS in the checkout being tested, resolved from the repo root.
#
# WHY THE REPO ROOT IS THE RESOLUTION BASE: the sweeper runs every probe from there
# (`scheduled-followthrough-sweeper.yml` -> `bash scripts/sweep-followthroughs.sh` -> `env -i
# ... bash <script>`), so that is the directory a repo-relative literal actually resolves
# against at run time. Resolving against TARGET_DIR would be a different, weaker property.
#
# WHY `git ls-files` AND NOT `-e`: a worktree carries untracked files, so `-e` passes locally
# on an untracked artefact and reddens in CI. Tracked-ness removes that whole class. The
# compared value is the tracked file set, which the SAME commit can move -- that is the point:
# a rename that forgets the probe reddens the PR that renamed it. Directories count as
# existing when any tracked file sits under them (a probe may legitimately cite a directory).
#
# THE `# repo-path: runtime` OPT-OUT IS PER LINE, NOT PER FILE. A file-scoped skip would pass
# every row a naive matrix writes while silently exempting a real rot target -- the exact
# failure this rule exists for. Its real user today is
# `inngest-cutover-flip-rollout-7761.sh`'s `AFTER_FILE`: untracked, absent, read only if
# readable, and written by the operator in response to the probe's own output.
#
# DECLARED BLIND SPOTS (named, not silent): a path built by concatenation across lines or by
# `printf -v`; a path assembled inside `$(cd ... && pwd)`; anything containing `..` (a
# `$HERE/../../apps/...` script-relative literal is NOT normalised and is NOT checked); a
# second path literal on a line that already yielded one; a path whose TOP-LEVEL directory is
# not currently tracked (`plausible()` keys on the tracked top-dir set, so renaming a whole
# top-level directory makes every reference into it silently unplausible rather than missing --
# the one case where this rule degrades toward quiet); and anything in a `*.test.sh`
# (rule 1's exclusion, load-bearing here because `ccla-representative-icla-7922.test.sh`
# assigns a gitignored `node_modules/.bin/tsx` path that exists locally and not in the
# `test-scripts` CI shard). A value that is a regex/glob pattern, a URL, or carries an
# unresolved `$` is ignored by construction.
#
# Rules 1 and 3 share `exit 1` because both mean the same thing to the author: fix the probe.
# Rule 3 has its OWN counters (`scanned_rule3`, `refs_rule3`, `missing_rule3`) and its OWN two
# floors, so neither rule's floor vouches for another's walk. The two floors are distinct on
# purpose: a broken GLOB and a broken REGEX are different vacuity modes, and the messages say
# which.
#
# Usage:  lint-followthrough-varq-ban.sh [TARGET_DIR]
#   no arg      -> scans <repo-root>/scripts/followthroughs (production run; ≥10-file floor)
#   TARGET_DIR  -> scans that dir verbatim (how the .test.sh points it at a mktemp sandbox)
#
# Exit: 0 = no violations; 1 = one or more violations; 2 = internal error (dir absent, or a
#       production run whose probe count falls below the min-cardinality floor -> broken glob).

set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
DEFAULT_DIR="${REPO_ROOT:-.}/scripts/followthroughs"
TARGET_DIR="${1:-$DEFAULT_DIR}"

if [[ ! -d "$TARGET_DIR" ]]; then
  echo "ERROR: target dir not found: $TARGET_DIR" >&2
  exit 2
fi

# The min-cardinality floor keys on the RESOLVED target dir, not on arg-presence: a caller
# passing the real dir explicitly (lint-followthrough-varq-ban.sh scripts/followthroughs)
# must not silently bypass the vacuity floor; a mktemp sandbox dir never resolves to the
# default, so the floor is skipped there (deepen-plan finding).
resolve() { (cd "$1" 2>/dev/null && pwd -P) || echo "$1"; }
is_production_run="no"
if [[ "$(resolve "$TARGET_DIR")" == "$(resolve "$DEFAULT_DIR")" ]]; then
  is_production_run="yes"
fi

violations=0
scanned=0
# RULE 1: the banned `${VAR:?}` / `${VAR?}` word-expansion on an executable line.
for f in "$TARGET_DIR"/*.sh; do
  [[ -e "$f" ]] || continue
  case "$f" in
    *.test.sh) continue ;;
  esac
  scanned=$((scanned + 1))
  # grep -n on the RAW file FIRST (correct line numbers), THEN drop full-line comments.
  while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    lineno="${hit%%:*}"
    echo "$f:$lineno: banned \${VAR:?} / \${VAR?} form on an executable line -- use 'if [[ -z \"\${VAR:-}\" ]]; then echo \"TRANSIENT: ...\" >&2; exit 2; fi'" >&2
    violations=$((violations + 1))
  done < <(grep -nE '\$\{[A-Za-z_][A-Za-z0-9_]*:?\?' "$f" | grep -vE '^[0-9]+:[[:space:]]*#')
done

# RULE 2: the retired credential name in ANY file under the dir, at any depth, comments
# INCLUDED -- one recursive grep, not a `*.sh` glob, so a fixture, a `.md` note or a
# subdirectory cannot carry it past the ban. `-F` because the needle is a literal (a
# superstring such as `MY_SENTRY_AUTH_TOKEN` is caught on purpose: it is the same name with a
# prefix); `-n` on the RAW file so the cited line is the true one. The `# rule2-grep` marker
# is what the suite's M5 row deletes to prove this line is the mechanism.
RETIRED_NAME='SENTRY_AUTH_TOKEN'
scanned_rule2=$(find "$TARGET_DIR" -type f | wc -l)  # rule2-count
rule2_hits=""
rule2_hits=$(grep -rnF -- "$RETIRED_NAME" "$TARGET_DIR" || true)  # rule2-grep
while IFS= read -r hit; do
  [[ -z "$hit" ]] && continue
  # `path:line:text` -- the path is the first field; the line number the second.
  f="${hit%%:*}"; rest="${hit#*:}"; lineno="${rest%%:*}"
  echo "$f:$lineno: rule 2: names the retired credential '$RETIRED_NAME' -- use SENTRY_ACTIONS_RO_TOKEN; the retired name binds a personal token under doppler run -c prd_terraform (see ADR-031, #7946). Comments, fixtures and .test.sh stubs count: they are what gets copied." >&2
  violations=$((violations + 1))
done <<<"$rule2_hits"

# RULE 4: no probe may FILTER on `authorAssociation`. The trusted-verdict decision belongs to
# scripts/lib/trusted-verdict.sh and nowhere else, which is what makes "the lib is the
# chokepoint" a fact rather than an assertion: a probe cannot re-inline its own filter and stay
# green.
#
# WHY IT IS BANNED. `authorAssociation` is computed against the READING token's visibility, so
# under the sweeper's `GITHUB_TOKEN` an org member whose membership is PRIVATE renders as
# CONTRIBUTOR and their verdict is dropped SILENTLY. Measured on #6617: the operator posted
# `RESULT: PASS` on 2026-07-20 and the nightly sweeper reported FAIL for two months against an
# issue whose verdict was already recorded. Effective repository permission does not depend on
# membership visibility, so the lib resolves that instead.
#
# ANCHORED ON THE FILTER SHAPE, NOT THE BARE WORD — and this is the difference between a rule
# that can be documented and one that cannot. Rule 2 bans a bare literal everywhere including
# comments, which is right for a credential name. Here the bare word appears in every probe's
# header explaining WHY not to use it, so a bare-word ban would false-fire on its own rationale
# and force the explanation out of the file (cq-assert-anchor-not-bare-token). The property is
# "no probe FILTERS on it", so the anchors are the comparison and the `select()` — a read for
# reporting, e.g. printing the observed value, is not a filter and is not banned.
BANNED_FILTER='\.authorAssociation[[:space:]]*(==|!=)|select\([^)]*\.authorAssociation'
scanned_rule4=$(find "$TARGET_DIR" -type f | wc -l)  # rule4-count
rule4_hits=""
rule4_hits=$(grep -rnE -- "$BANNED_FILTER" "$TARGET_DIR" | grep -vE ':[0-9]+:[[:space:]]*#' || true)  # rule4-grep
while IFS= read -r hit; do
  [[ -z "$hit" ]] && continue
  f="${hit%%:*}"; rest="${hit#*:}"; lineno="${rest%%:*}"
  echo "$f:$lineno: rule 4: filters on 'authorAssociation' -- source scripts/lib/trusted-verdict.sh and call trusted_verdict_bodies instead. authorAssociation is computed against the READING token's visibility, so a member with PRIVATE org membership renders as CONTRIBUTOR under GITHUB_TOKEN and their verdict is dropped silently (#6617: two months of nightly FAIL on an already-recorded verdict)." >&2
  violations=$((violations + 1))
done <<<"$rule4_hits"

# RULE 3: repo-relative path literals must name something that exists in the checkout.
# The tracked set is files PLUS every ancestor directory of a tracked file, so a probe that
# legitimately cites a DIRECTORY is not reported as a miss.
#
# The census program is held in a quoted heredoc rather than inlined in `awk '...'`: the
# program's own body carries both `"` and `$`, and nesting it inside a single-quoted shell
# word needs `'"'"'` seams that are a parse hazard in exactly the way this repo's own rules
# warn about. A variable keeps the program readable and the quoting trivially correct.
read -r -d '' RULE3_AWK <<'RULE3_AWK_EOF' || true
function cut_at(rest,   i, c, out) {
  out = ""
  for (i = 1; i <= length(rest); i++) {
    c = substr(rest, i, 1)
    if (c == "\"" || c == "}" || c == " " || c == "\t") break
    out = out c
  }
  return out
}
function plausible(p,   top) {
  if (p == "") return 0
  if (index(p, "/") == 0) return 0
  if (p ~ /\$/) return 0
  if (p ~ /\.\./) return 0
  if (p ~ /[][*?\\()|^]/) return 0
  if (p ~ /:\/\//) return 0
  top = p; sub(/\/.*/, "", top)
  if (index(TOPDIRS, "|" top "|") == 0) return 0
  return 1
}
{
  line = $0
  if (line ~ /^[ \t]*#/) next
  if (line ~ /#[ \t]*repo-path:[ \t]*runtime/) next
  if (line !~ /^[ \t]*(local[ \t]+|export[ \t]+|readonly[ \t]+|declare[ \t]+-[a-zA-Z]+[ \t]+)?[A-Za-z_][A-Za-z0-9_]*=/ && line !~ /^[ \t]*(source|\.)[ \t]/) next
  cand = ""; arm = ""
  if (match(line, /"\$\{[A-Za-z_][A-Za-z0-9_]*:-\$\{[A-Za-z_][A-Za-z0-9_]*\}\//)) {
    cand = cut_at(substr(line, RSTART + RLENGTH)); arm = "braced-default"
  } else if (match(line, /"\$\{[A-Za-z_][A-Za-z0-9_]*:-\$[A-Za-z_][A-Za-z0-9_]*\//)) {
    cand = cut_at(substr(line, RSTART + RLENGTH)); arm = "bare-default"
  } else if (match(line, /"\$\{[A-Za-z_][A-Za-z0-9_]*:-/)) {
    # Capture the default DIRECTLY. The first version walked backwards to the nearest `-`,
    # which is the `-` of `:-` only when the first path segment is hyphen-free -- so
    # `${OV:-knowledge-base/...}` yielded `base/legal/...`, whose top segment is not a tracked
    # directory, and `plausible()` dropped the whole reference with no diagnostic. That is a
    # silent MISS in the arm's own most likely shape: `knowledge-base/` is this repo's
    # commonest repo-relative prefix. Measured: a seeded probe with one `knowledge-base/` and
    # one `scripts/` absent default reported ONE miss, not two.
    rest = substr(line, RSTART + RLENGTH)
    if (rest ~ /^[A-Za-z0-9_.-]+\//) { cand = cut_at(rest); arm = "literal-default" }
  } else if (match(line, /"\$\{[A-Za-z_][A-Za-z0-9_]*\}\//)) {
    cand = cut_at(substr(line, RSTART + RLENGTH)); arm = "braced"
  } else if (match(line, /"\$[A-Za-z_][A-Za-z0-9_]*\//)) {
    cand = cut_at(substr(line, RSTART + RLENGTH)); arm = "bare"
  } else if (match(line, /"[A-Za-z0-9_.-]+\//)) {
    cand = cut_at(substr(line, RSTART + 1)); arm = "literal"
  }
  if (cand != "" && plausible(cand)) printf "%d\t%s\t%s\n", FNR, cand, arm
}
RULE3_AWK_EOF

tracked_list="$( (cd "${REPO_ROOT:-.}" 2>/dev/null && git ls-files 2>/dev/null) || true )"
# The membership set is written to a FILE and grepped as a file operand -- never
# `printf ... | grep -qxF`. Under this script's `set -o pipefail`, `grep -q` closes the pipe on
# its FIRST match, the producer takes SIGPIPE (141), and the pipeline exits non-zero although
# grep matched -- so every tracked path would report as MISSING and the guard would be
# false-RED on a clean tree. The failure is invisible for a small producer and certain for this
# one (~18k lines, and the matches are early). Measured on this very file before the fix: 22
# tracked paths reported missing. Same trap as the `grep -q`-on-a-pipe ban the repo's own work
# rules carry. A file operand also makes it one open per reference instead of an 18k-line
# re-serialisation.
tracked_set_file="$(mktemp -t ft-tracked-set.XXXXXXXX)"
trap 'rm -f "$tracked_set_file"' EXIT
# Files plus every ancestor directory, so a probe citing a DIRECTORY is not a miss.
printf '%s\n' "$tracked_list" \
  | awk -F/ '{print; p=""; for (i=1;i<NF;i++) { p=(p==""?$i:p"/"$i); print p }}' \
  | sort -u > "$tracked_set_file"
TOPDIRS="|$(printf '%s\n' "$tracked_list" | grep / | cut -d/ -f1 | grep -xE '[A-Za-z0-9._-]+' | sort -u | paste -sd'|' -)|"

scanned_rule3=0
refs_rule3=0
missing_rule3=0
for f in "$TARGET_DIR"/*.sh; do
  [[ -e "$f" ]] || continue
  case "$f" in
    *.test.sh) continue ;;
  esac
  scanned_rule3=$((scanned_rule3 + 1))
  while IFS=$'\t' read -r lineno cand arm; do
    [[ -z "${cand:-}" ]] && continue
    refs_rule3=$((refs_rule3 + 1))
    if ! grep -qxF -- "$cand" "$tracked_set_file"; then
      echo "$f:$lineno: rule 3: MISSING $f -> $cand [$arm] -- not tracked in this checkout; the sweeper runs probes from the repo root, so this literal resolves to nothing. Repoint it, or annotate THAT LINE with '# repo-path: runtime' if the artefact is written at run time." >&2
      missing_rule3=$((missing_rule3 + 1))   # rule3-missing
      violations=$((violations + 1))
    fi
  done < <(awk -v TOPDIRS="$TOPDIRS" "$RULE3_AWK" "$f")   # rule3-census
done

# Rule 3's TWO floors. MIN_REF_FILES guards the GLOB (files walked); MIN_REFS guards the
# REGEX (references extracted). A neutered regex walks every file and finds nothing, which the
# file floor cannot see -- which is why there are two, with two messages naming which broke.
# REPO_PATHS_MIN_REFS / REPO_PATHS_MIN_REF_FILES are TEST-ONLY overrides (mirroring
# VARQ_BAN_MIN_PROBES); production CI never sets them. Both defaults were DERIVED from one run
# of the committed census above, measured 2026-09-18 on the repointed tree: rule 3 WALKED 74
# non-test probes and EXTRACTED 44 references from 29 of them. The two numbers count different
# things and the floors must too -- `scanned_rule3` is every probe walked (74), not the 29 that
# happen to carry a reference -- so the file floor sits just under the walk and the ref floor
# just under the extraction. Slack is deliberate but small: refs are not one-per-file, and a
# probe that legitimately loses its last path literal should not red the tree.
MIN_REF_FILES="${REPO_PATHS_MIN_REF_FILES:-70}"
MIN_REFS="${REPO_PATHS_MIN_REFS:-40}"
if [[ "$is_production_run" == "yes" ]] && (( scanned_rule3 < MIN_REF_FILES )); then
  echo "ERROR: rule 3 walked only $scanned_rule3 probe file(s) in $TARGET_DIR -- expected at least $MIN_REF_FILES; the GLOB or path is broken" >&2
  exit 2
fi
if [[ "$is_production_run" == "yes" ]] && (( refs_rule3 < MIN_REFS )); then
  echo "ERROR: rule 3 extracted only $refs_rule3 repo-path reference(s) from $scanned_rule3 file(s) -- expected at least $MIN_REFS; the census REGEX is broken (the walk is not: it saw $scanned_rule3 files)" >&2
  exit 2
fi

# Minimum-cardinality floor (production run only): a broken glob yielding 0 files must not
# pass vacuously. Skipped for an explicit sandbox dir (the .test.sh fixtures are few).
# VARQ_BAN_MIN_PROBES is a TEST-ONLY override so the .test.sh can force a floor breach on the
# real tree (set it above the probe count) and prove exit 2 fires; production CI never sets it
# and gets the default 10.
MIN_PROBES="${VARQ_BAN_MIN_PROBES:-10}"
if [[ "$is_production_run" == "yes" ]] && (( scanned < MIN_PROBES )); then
  echo "ERROR: only $scanned non-test probe(s) scanned in $TARGET_DIR -- expected the full set; the glob or path is broken" >&2
  exit 2
fi
# Rule 2's own floor, keyed on ITS counter: a rule-2 walk that resolves nothing must not
# report clean over nothing, and rule 1's count must not be what vouches for it.
if [[ "$is_production_run" == "yes" ]] && (( scanned_rule2 < MIN_PROBES )); then
  echo "ERROR: rule 2 (retired-name ban) checked only $scanned_rule2 file(s) in $TARGET_DIR -- its walk resolved nothing; the glob or path is broken" >&2
  exit 2
fi
# Rule 4's own floor, keyed on ITS counter for the same reason: no rule's floor may vouch for
# another's walk.
if [[ "$is_production_run" == "yes" ]] && (( scanned_rule4 < MIN_PROBES )); then
  echo "ERROR: rule 4 (authorAssociation filter ban) checked only $scanned_rule4 file(s) in $TARGET_DIR -- its walk resolved nothing; the glob or path is broken" >&2
  exit 2
fi

if (( violations > 0 )); then
  echo "FAILED: $violations violation(s) -- banned \${VAR:?}/\${VAR?} on an executable line (rule 1), the retired credential name (rule 2), a repo-relative path absent from this checkout (rule 3), and/or an inline authorAssociation filter (rule 4). See followthrough-convention.md §Author workflow." >&2
  exit 1
fi

echo "followthrough-varq-ban: clean ($scanned probe(s) scanned; retired-name rule checked $scanned_rule2 file(s) in $TARGET_DIR; rule 3 walked $scanned_rule3 file(s), extracted $refs_rule3 repo-path ref(s), $missing_rule3 missing; rule 4 (authorAssociation filter ban) checked $scanned_rule4 file(s))"
exit 0
